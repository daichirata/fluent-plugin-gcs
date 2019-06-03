require "tempfile"
require "zlib"
require "lzo"


module Fluent
  module GCS
    def self.discovered_object_creator(store_as, transcoding: nil)
      case store_as
      when :gzip
        Fluent::GCS::GZipObjectCreator.new(transcoding)
      when :json
        Fluent::GCS::JSONObjectCreator.new
      when :text
        Fluent::GCS::TextObjectCreator.new
      when :lzo
        Fluent::GCS::LzoObjectCreator.new(transcoding)
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

    class LzoObjectCreator < ObjectCreator
      def initialize(transcoding)
        @transcoding = transcoding
      end

      def content_type
        @transcoding ? "text/plain" : "application/x-lzo"
      end

      def content_encoding
        @transcoding ? "lzop" : nil
      end

      def file_extension
        "lzo"
      end

      def write(chunk, io)
        writer = LZO::LzopCompressor.new io, name: '', mode: 0100644, mtime: Time.now
        chunk.write_to(writer)
        writer.close # need to close, as LzopCompressor writes LZO end symbols
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
