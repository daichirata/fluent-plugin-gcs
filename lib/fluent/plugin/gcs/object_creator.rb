require "tempfile"
require "zlib"
require "open3"
require "shellwords"

module Fluent
  module GCS
    def self.discovered_object_creator(store_as, transcoding: nil, command_parameter: nil, log: nil)
      case store_as
      when :gzip
        Fluent::GCS::GZipObjectCreator.new(transcoding)
      when :gzip_command
        Fluent::GCS::GZipCommandObjectCreator.new(
          transcoding: transcoding,
          command_parameter: command_parameter,
          log: log
        )
      when :json
        Fluent::GCS::JSONObjectCreator.new
      when :text
        Fluent::GCS::TextObjectCreator.new
      end
    end

    class ObjectCreator
      def content_type
        raise NotImplementedError
      end

      def content_encoding
        nil
      end

      def file_extension
        raise NotImplementedError
      end

      def write(chunk, io)
        raise NotImplementedError
      end

      def create(chunk, &block)
        Tempfile.create("fluent-plugin-gcs") do |f|
          f.binmode
          f.sync = true
          write(chunk, f)
          block.call(f)
        end
      end
    end

    class GZipObjectCreator < ObjectCreator
      def initialize(transcoding)
        @transcoding = transcoding
      end

      def content_type
        @transcoding ? "text/plain" : "application/gzip"
      end

      def content_encoding
        @transcoding ? "gzip" : nil
      end

      def file_extension
        "gz"
      end

      def write(chunk, io)
        writer = Zlib::GzipWriter.new(io)
        chunk.write_to(writer)
        writer.finish
      end
    end

    class GZipCommandObjectCreator < ObjectCreator
      def initialize(transcoding:, command_parameter:, log:)
        @transcoding = transcoding
        @command_parameter = command_parameter || ""
        @log = log
        check_gzip_command
      end

      def content_type
        @transcoding ? "text/plain" : "application/gzip"
      end

      def content_encoding
        @transcoding ? "gzip" : nil
      end

      def file_extension
        "gz"
      end

      def write(chunk, io)
        cmd = ["gzip", *@command_parameter.shellsplit, "-c"]
        status = Open3.pipeline_w(cmd, out: io.path) do |stdin, wait_thrs|
          chunk.write_to(stdin)
          stdin.close
          wait_thrs.last.value
        end

        unless status.success?
          @log&.warn("failed to execute gzip command. Fallback to GzipWriter. status = #{status}")
          io.truncate(0)
          io.rewind
          fallback_to_gzip_writer(chunk, io)
        end
      end

      private

      def check_gzip_command
        begin
          Open3.capture3("gzip -V")
        rescue Errno::ENOENT
          raise Fluent::ConfigError, "'gzip' utility must be in PATH for gzip_command compression"
        end
      end

      def fallback_to_gzip_writer(chunk, io)
        writer = Zlib::GzipWriter.new(io)
        chunk.write_to(writer)
        writer.finish
      end
    end

    class TextObjectCreator < ObjectCreator
      def content_type
        "text/plain"
      end

      def file_extension
        "txt"
      end

      def write(chunk, io)
        chunk.write_to(io)
      end
    end

    class JSONObjectCreator < TextObjectCreator
      def content_type
        "application/json"
      end

      def file_extension
        "json"
      end
    end
  end
end
