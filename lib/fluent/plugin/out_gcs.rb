require "digest/md5"
require "securerandom"
require "socket"

require "fluent/plugin/gcs/object_creator"
require "fluent/plugin/gcs/version"
require "fluent/plugin/output"

module Fluent::Plugin
  class GCSOutput < Output
    Fluent::Plugin.register_output("gcs", self)

    helpers :compat_parameters, :formatter, :inject

    def initialize
      super
      require "google/cloud/storage"
      Google::Apis.logger = log
    end

    config_param :project, :string,  default: nil,
                 desc: "Project identifier for GCS"
    config_param :keyfile, :string, default: nil,
                 desc: "Path of GCS service account credentials JSON file"
    config_param :credentials_json, :hash, default: nil, secret: true,
                 desc: "GCS service account credentials in JSON format"
    config_param :client_retries, :integer, default: nil,
                 desc: "Number of times to retry requests on server error"
    config_param :client_timeout, :integer, default: nil,
                 desc: "Default timeout to use in requests"
    config_param :bucket, :string,
                 desc: "Name of a GCS bucket"
    config_param :object_key_format, :string, default: "%{path}%{time_slice}_%{index}.%{file_extension}",
                 desc: "Format of GCS object keys"
    config_param :path, :string, default: "",
                 desc: "Path prefix of the files on GCS"
    config_param :store_as, :enum, list: %i(gzip json text), default: :gzip,
                 desc: "Archive format on GCS"
    config_param :transcoding, :bool, default: false,
                 desc: "Enable the decompressive form of transcoding"
    config_param :auto_create_bucket, :bool, default: true,
                 desc: "Create GCS bucket if it does not exists"
    config_param :hex_random_length, :integer, default: 4,
                 desc: "Max length of `%{hex_random}` placeholder(4-16)"
    config_param :overwrite, :bool, default: false,
                 desc: "Overwrite already existing path"
    config_param :format, :string, default: "out_file",
                 desc: "Change one line format in the GCS object"
    config_param :acl, :enum, list: %i(auth_read owner_full owner_read private project_private public_read), default: nil,
                 desc: "Permission for the object in GCS"
    config_param :storage_class, :enum, list: %i(dra nearline coldline multi_regional regional standard), default: nil,
                 desc: "Storage class of the file"
    config_param :encryption_key, :string, default: nil, secret: true,
                 desc: "Customer-supplied, AES-256 encryption key"
    config_param :blind_write, :bool, default: false,
                 desc: "Whether to check if object already exists by given GCS path. Allows avoiding giving storage.object.get permission"
    config_section :object_metadata, required: false do
      config_param :key, :string, default: ""
      config_param :value, :string, default: ""
    end

    DEFAULT_FORMAT_TYPE = "out_file"

    config_section :format do
      config_set_default :@type, DEFAULT_FORMAT_TYPE
    end

    config_section :buffer do
      config_set_default :chunk_keys, ['time']
      config_set_default :timekey, (60 * 60 * 24)
    end

    MAX_HEX_RANDOM_LENGTH = 32

    def configure(conf)
      compat_parameters_convert(conf, :buffer, :formatter, :inject)
      super

      if @hex_random_length > MAX_HEX_RANDOM_LENGTH
        raise Fluent::ConfigError, "hex_random_length parameter should be set to #{MAX_HEX_RANDOM_LENGTH} characters or less."
      end

      # The customer-supplied, AES-256 encryption key that will be used to encrypt the file.
      @encryption_opts = {
        encryption_key: @encryption_key,
      }

      if @object_metadata
        @object_metadata_hash = @object_metadata.map {|m| [m.key, m.value] }.to_h
      end

      @formatter = formatter_create

      @object_creator = Fluent::GCS.discovered_object_creator(@store_as, transcoding: @transcoding)
      # For backward compatibility
      # TODO: Remove time_slice_format when end of support compat_parameters
      @configured_time_slice_format = conf['time_slice_format']
      @time_slice_with_tz = Fluent::Timezone.formatter(@timekey_zone, @configured_time_slice_format || timekey_to_timeformat(@buffer_config['timekey']))

      if @credentials_json
        @credentials = @credentials_json
      else
        @credentials = keyfile
      end
    end

    def start
      @gcs = Google::Cloud::Storage.new(
        project: @project,
        keyfile: @credentials,
        retries: @client_retries,
        timeout: @client_timeout
      )
      @gcs_bucket = @gcs.bucket(@bucket)

      ensure_bucket
      super
    end

    def format(tag, time, record)
      r = inject_values_to_record(tag, time, record)
      @formatter.format(tag, time, r)
    end

    def multi_workers_ready?
      true
    end

    def write(chunk)
      path = generate_path(chunk)

      @object_creator.create(chunk) do |obj|
        opts = {
          metadata: @object_metadata_hash,
          acl: @acl,
          storage_class: @storage_class,
          content_type: @object_creator.content_type,
          content_encoding: @object_creator.content_encoding,
        }
        opts.merge!(@encryption_opts)

        log.debug { "out_gcs: upload chunk:#{chunk.key} to gcs://#{@bucket}/#{path} options: #{opts}" }
        @gcs_bucket.upload_file(obj.path, path, **opts)
      end
    end

    private

    def ensure_bucket
      return unless @gcs_bucket.nil?

      if !@auto_create_bucket
        raise "bucket `#{@bucket}` does not exist"
      end
      log.info "creating bucket `#{@bucket}`"
      @gcs_bucket = @gcs.create_bucket(@bucket)
    end

    def hex_random(chunk)
      Digest::MD5.hexdigest(chunk.unique_id)[0...@hex_random_length]
    end

    def check_object_exists(path)
      if !@blind_write
        return @gcs_bucket.find_file(path, **@encryption_opts)
      else
        return false
      end
    end

    def generate_path(chunk)
      metadata = chunk.metadata
      time_slice = if metadata.timekey.nil?
                     ''.freeze
                   else
                     @time_slice_with_tz.call(metadata.timekey)
                   end
      tags = {
        "%{file_extension}" => @object_creator.file_extension,
        "%{hex_random}" => hex_random(chunk),
        "%{hostname}" => Socket.gethostname,
        "%{path}" => @path,
        "%{time_slice}" => time_slice,
      }

      prev = nil
      i = 0

      until i < 0 do # Until overflow
        tags["%{uuid_flush}"] = SecureRandom.uuid
        tags["%{index}"] = i

        path = @object_key_format.gsub(Regexp.union(tags.keys), tags)
        path = extract_placeholders(path, chunk)
        return path unless check_object_exists(path)

        if path == prev
          if @overwrite
            log.warn "object `#{path}` already exists but overwrites it"
            return path
          end
          raise "object `#{path}` already exists"
        end

        i += 1
        prev = path
      end

      raise "cannot find an unoccupied GCS path"
    end

    # This is stolen from Fluentd
    def timekey_to_timeformat(timekey)
      case timekey
      when nil          then ''
      when 0...60       then '%Y%m%d%H%M%S' # 60 exclusive
      when 60...3600    then '%Y%m%d%H%M'
      when 3600...86400 then '%Y%m%d%H'
      else                   '%Y%m%d'
      end
    end
  end
end
