require "helper"
require "zlib"
require "tmpdir"

class GCSObjectCreatorTest < Test::Unit::TestCase
  DUMMY_DATA = %[2016-01-01T12:00:00Z\ttest\t{"a":1,"tag":"test","time":"2016-01-01T12:00:00Z"}\n] +
               %[2016-01-01T12:00:00Z\ttest\t{"a":2,"tag":"test","time":"2016-01-01T12:00:00Z"}\n]

  class DummyChunk
    def write_to(io)
      io.write DUMMY_DATA
    end
  end

  class DummyObjectCreator < Fluent::GCS::ObjectCreator
    attr_reader :written

    def content_type
      "text/plain"
    end

    def file_extension
      "txt"
    end

    def write(chunk, io)
      @written = true
      chunk.write_to(io)
    end
  end

  sub_test_case "GZipObjectCreator" do
    def test_content_type_and_content_encoding
      c = Fluent::GCS::GZipObjectCreator.new(true)
      assert_equal "text/plain", c.content_type
      assert_equal "gzip", c.content_encoding

      c = Fluent::GCS::GZipObjectCreator.new(false)
      assert_equal "application/gzip", c.content_type
      assert_equal nil, c.content_encoding
    end

    def test_file_extension
      c = Fluent::GCS::GZipObjectCreator.new(true)
      assert_equal "gz", c.file_extension

      c = Fluent::GCS::GZipObjectCreator.new(false)
      assert_equal "gz", c.file_extension
    end

    def test_write
      Tempfile.create("test_object_creator") do |f|
        f.binmode
        f.sync = true

        c = Fluent::GCS::GZipObjectCreator.new(true)
        c.write(DummyChunk.new, f)
        Zlib::GzipReader.open(f.path) do |gz|
          assert_equal DUMMY_DATA, gz.read
        end

        f.rewind
        c = Fluent::GCS::GZipObjectCreator.new(false)
        c.write(DummyChunk.new, f)
        Zlib::GzipReader.open(f.path) do |gz|
          assert_equal DUMMY_DATA, gz.read
        end
      end
    end
  end

  sub_test_case "GZipCommandObjectCreator" do
    class DummyLog
      attr_reader :warnings

      def initialize
        @warnings = []
      end

      def warn(message)
        @warnings << message
      end
    end

    def test_content_type_and_content_encoding
      c = Fluent::GCS::GZipCommandObjectCreator.new(transcoding: true, command_parameter: "", log: nil)
      assert_equal "text/plain", c.content_type
      assert_equal "gzip", c.content_encoding

      c = Fluent::GCS::GZipCommandObjectCreator.new(transcoding: false, command_parameter: "", log: nil)
      assert_equal "application/gzip", c.content_type
      assert_equal nil, c.content_encoding
    end

    def test_file_extension
      c = Fluent::GCS::GZipCommandObjectCreator.new(transcoding: true, command_parameter: "", log: nil)
      assert_equal "gz", c.file_extension

      c = Fluent::GCS::GZipCommandObjectCreator.new(transcoding: false, command_parameter: "", log: nil)
      assert_equal "gz", c.file_extension
    end

    def test_write
      Tempfile.create("test_object_creator") do |f|
        f.binmode
        f.sync = true

        c = Fluent::GCS::GZipCommandObjectCreator.new(transcoding: true, command_parameter: "", log: nil)
        c.write(DummyChunk.new, f)
        Zlib::GzipReader.open(f.path) do |gz|
          assert_equal DUMMY_DATA, gz.read
        end
      end
    end

    def test_write_with_command_parameter
      Tempfile.create("test_object_creator") do |f|
        f.binmode
        f.sync = true

        c = Fluent::GCS::GZipCommandObjectCreator.new(transcoding: false, command_parameter: "-1", log: nil)
        c.write(DummyChunk.new, f)
        Zlib::GzipReader.open(f.path) do |gz|
          assert_equal DUMMY_DATA, gz.read
        end
      end
    end

    def test_write_fallback_to_gzip_writer_on_command_failure
      Dir.mktmpdir do |bin_dir|
        fake_gzip = File.join(bin_dir, "gzip")
        File.write(fake_gzip, "#!/bin/sh\nexit 1\n")
        File.chmod(0755, fake_gzip)

        original_path = ENV["PATH"]
        ENV["PATH"] = "#{bin_dir}:#{original_path}"
        begin
          Tempfile.create("test_object_creator") do |f|
            f.binmode
            f.sync = true

            log = DummyLog.new
            c = Fluent::GCS::GZipCommandObjectCreator.new(transcoding: false, command_parameter: "", log: log)
            c.write(DummyChunk.new, f)

            assert_equal 1, log.warnings.size
            assert_match(/Fallback to GzipWriter/, log.warnings.first)

            Zlib::GzipReader.open(f.path) do |gz|
              assert_equal DUMMY_DATA, gz.read
            end
          end
        ensure
          ENV["PATH"] = original_path
        end
      end
    end

    def test_initialize_raises_config_error_when_gzip_is_not_in_path
      Open3.expects(:capture3).with("gzip -V").raises(Errno::ENOENT)

      err = assert_raise(Fluent::ConfigError) do
        Fluent::GCS::GZipCommandObjectCreator.new(transcoding: false, command_parameter: "", log: nil)
      end
      assert_equal "'gzip' utility must be in PATH for gzip_command compression", err.message
    end

  end

  sub_test_case "ObjectCreator" do
    def test_create_yields_binmode_tempfile_with_written_content
      creator = DummyObjectCreator.new

      creator.create(DummyChunk.new) do |f|
        assert_equal true, creator.written
        assert_equal true, f.binmode?
        assert_equal true, f.sync
        f.rewind
        assert_equal DUMMY_DATA, f.read
      end
    end
  end

  sub_test_case "TextObjectCreator" do
    def test_content_type_and_content_encoding
      c = Fluent::GCS::TextObjectCreator.new
      assert_equal "text/plain", c.content_type
      assert_equal nil, c.content_encoding
    end

    def test_file_extension
      c = Fluent::GCS::TextObjectCreator.new
      assert_equal "txt", c.file_extension
    end

    def test_write
      Tempfile.create("test_object_creator") do |f|
        f.binmode
        f.sync = true

        c = Fluent::GCS::TextObjectCreator.new
        c.write(DummyChunk.new, f)
        f.rewind
        assert_equal DUMMY_DATA, f.read
      end
    end
  end

  sub_test_case "JSONObjectCreator" do
    def test_content_type_and_content_encoding
      c = Fluent::GCS::JSONObjectCreator.new
      assert_equal "application/json", c.content_type
      assert_equal nil, c.content_encoding
    end

    def test_file_extension
      c = Fluent::GCS::JSONObjectCreator.new
      assert_equal "json", c.file_extension
    end

    def test_write
      Tempfile.create("test_object_creator") do |f|
        f.binmode
        f.sync = true

        c = Fluent::GCS::JSONObjectCreator.new
        c.write(DummyChunk.new, f)
        f.rewind
        assert_equal DUMMY_DATA, f.read
      end
    end
  end
end
