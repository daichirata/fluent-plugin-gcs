require "digest/md5"
require "securerandom"
require "socket"

require "fluent/plugin/gcs/object_creator"
require "fluent/plugin/gcs/version"

module Fluent
  class GCSOutput < TimeSlicedOutput
    Fluent::Plugin.register_output("gcs", self)

    def initialize
      super
      require "google/cloud/storage"
    end

    config_param :project, :string,  default: nil,
                 desc: "Project identifier for GCS"
    config_param :keyfile, :string, default: nil,
                 desc: "Path of GCS service account credentials JSON file"
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
    config_param :store_as, :enum, list: %i(gzip json text lzo), default: :gzip,
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
    config_section :object_metadata, required: false do
      config_param :key, :string, default: ""
      config_param :value, :string, default: ""
    end

    MAX_HEX_RANDOM_LENGTH = 32

    def configure(conf)
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

      @formatter = Fluent::Plugin.new_formatter(@format)
      @formatter.configure(conf)

      @object_creator = Fluent::GCS.discovered_object_creator(@store_as, transcoding: @transcoding)
    end

    def start
      @gcs = Google::Cloud::Storage.new(
        project: @project,
        keyfile: @keyfile,
        retries: @client_retries,
        timeout: @client_timeout
      )
      @gcs_bucket = @gcs.bucket(@bucket)

      ensure_bucket
      super
    end

    def format(tag, time, record)
      @formatter.format(tag, time, record)
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
        @gcs_bucket.upload_file(obj.path, path, opts)
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

    def format_path(chunk)
      now = Time.strptime(chunk.key, @time_slice_format)
      (@localtime ? now : now.utc).strftime(@path)
    end

    def generate_path(chunk, i = 0, prev = nil)
      tags = {
        "%{file_extension}" => @object_creator.file_extension,
        "%{hex_random}" => hex_random(chunk),
        "%{hostname}" => Socket.gethostname,
        "%{index}" => i,
        "%{path}" => format_path(chunk),
        "%{time_slice}" => chunk.key,
        "%{uuid_flush}" => SecureRandom.uuid,
      }
      path = @object_key_format.gsub(Regexp.union(tags.keys), tags)
      return path unless @gcs_bucket.find_file(path, @encryption_opts)

      if path == prev
        if @overwrite
          log.warn "object `#{path}` already exists but overwrites it"
          return path
        end
        raise "object `#{path}` already exists"
      end
      generate_path(chunk, i + 1, path)
    end
  end
end
