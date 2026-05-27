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
      when :lzo
        Fluent::GCS::LZOObjectCreator.new(command_parameter: command_parameter, log: log)
      when :lzma2
        Fluent::GCS::LZMA2ObjectCreator.new(command_parameter: command_parameter, log: log)
      when :zstd
        Fluent::GCS::ZstdObjectCreator.new(command_parameter: command_parameter, log: log)
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

    class CommandObjectCreator < ObjectCreator
      def initialize(command_parameter: nil, log: nil)
        @command_parameter = command_parameter
        @log = log
        check_command
      end

      def write(chunk, io)
        parameter = @command_parameter.nil? || @command_parameter.empty? ? default_parameter : @command_parameter
        cmd = [command, *parameter.shellsplit, "-c"]
        status = Open3.pipeline_w(cmd, out: io.path) do |stdin, wait_thrs|
          chunk.write_to(stdin)
          stdin.close
          wait_thrs.last.value
        end

        handle_failure(chunk, io, status) unless status.success?
      end

      private

      def command
        raise NotImplementedError
      end

      def store_as
        raise NotImplementedError
      end

      def default_parameter
        ""
      end

      def handle_failure(chunk, io, status)
        raise "failed to execute #{command} command. status = #{status}"
      end

      def check_command
        Open3.capture3(command, "--version")
      rescue Errno::ENOENT
        raise Fluent::ConfigError, "'#{command}' utility must be in PATH for #{store_as} compression"
      end
    end

    class GZipCommandObjectCreator < CommandObjectCreator
      def initialize(transcoding: nil, command_parameter: nil, log: nil)
        @transcoding = transcoding
        super(command_parameter: command_parameter, log: log)
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

      private

      def command
        "gzip"
      end

      def store_as
        "gzip_command"
      end

      def handle_failure(chunk, io, status)
        @log&.warn("failed to execute gzip command. Fallback to GzipWriter. status = #{status}")
        io.truncate(0)
        io.rewind
        writer = Zlib::GzipWriter.new(io)
        chunk.write_to(writer)
        writer.finish
      end
    end

    class LZOObjectCreator < CommandObjectCreator
      def content_type
        "application/x-lzop"
      end

      def file_extension
        "lzo"
      end

      private

      def command
        "lzop"
      end

      def default_parameter
        "-qf1"
      end

      def store_as
        "lzo"
      end
    end

    class LZMA2ObjectCreator < CommandObjectCreator
      def content_type
        "application/x-xz"
      end

      def file_extension
        "xz"
      end

      private

      def command
        "xz"
      end

      def default_parameter
        "-qf0"
      end

      def store_as
        "lzma2"
      end
    end

    class ZstdObjectCreator < CommandObjectCreator
      def content_type
        "application/x-zst"
      end

      def file_extension
        "zst"
      end

      private

      def command
        "zstd"
      end

      def store_as
        "zstd"
      end
    end
  end
end
