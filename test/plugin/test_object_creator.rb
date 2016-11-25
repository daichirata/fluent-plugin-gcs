require "helper"
require "zlib"

class GCSObjectCreatorTest < Test::Unit::TestCase
  DUMMY_DATA = %[2016-01-01T12:00:00Z\ttest\t{"a":1,"tag":"test","time":"2016-01-01T12:00:00Z"}\n] +
               %[2016-01-01T12:00:00Z\ttest\t{"a":2,"tag":"test","time":"2016-01-01T12:00:00Z"}\n]

  class DummyChunk
    def write_to(io)
      io.write DUMMY_DATA
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
