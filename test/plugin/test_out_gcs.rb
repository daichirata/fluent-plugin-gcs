require "helper"
require "google/cloud/storage"

class GCSOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = <<-EOC
    project test_project
    keyfile test_keyfile
    bucket test_bucket
    path log/
    buffer_type memory
    utc
  EOC

  def create_driver(conf = CONFIG)
    Fluent::Test::TimeSlicedOutputTestDriver.new(Fluent::GCSOutput) do
      attr_accessor :object_creator, :encryption_opts
    end.configure(conf)
  end

  def config(*args)
    args.join("\n")
  end

  sub_test_case "configure" do
    def test_configure
      driver = create_driver
      assert_equal "test_project", driver.instance.project
      assert_equal "test_keyfile", driver.instance.keyfile
      assert_equal "test_bucket", driver.instance.bucket
      assert_equal "%{path}%{time_slice}_%{index}.%{file_extension}", driver.instance.object_key_format
      assert_equal "log/", driver.instance.path
      assert_equal :gzip, driver.instance.store_as
      assert_equal false, driver.instance.transcoding
      assert_equal true, driver.instance.auto_create_bucket
      assert_equal 4, driver.instance.hex_random_length
      assert_equal false, driver.instance.overwrite
      assert_equal "out_file", driver.instance.instance_variable_get(:@format)
      assert_equal nil, driver.instance.acl
      assert_equal nil, driver.instance.encryption_key
      assert_equal nil, driver.instance.encryption_key_sha256
      assert_equal [], driver.instance.object_metadata
    end

    def test_configure_with_encryption_key
      assert_raise Fluent::ConfigError do
        create_driver(config(CONFIG, "encryption_key aaaaa"))
      end
      assert_nothing_raised do
        create_driver(config(CONFIG, "encryption_key aaaaa" , "encryption_key_sha256 bbbbbb"))
      end
    end

    def test_configure_with_hex_random_length
      assert_raise Fluent::ConfigError do
        create_driver(config(CONFIG, "hex_random_length 33"))
      end
      assert_nothing_raised do
        create_driver(config(CONFIG, "hex_random_length 32"))
      end
    end

    def test_configure_with_gzip_object_creator
      conf = config(CONFIG, "store_as gzip")
      driver = create_driver(conf)
      assert_equal true, driver.instance.object_creator.is_a?(Fluent::GCS::GZipObjectCreator)
    end

    def test_configure_with_text_object_creator
      conf = config(CONFIG, "store_as text")
      driver = create_driver(conf)
      assert_equal true, driver.instance.object_creator.is_a?(Fluent::GCS::TextObjectCreator)
    end

    def test_configure_with_json_object_creator
      conf = config(CONFIG, "store_as json")
      driver = create_driver(conf)
      assert_equal true, driver.instance.object_creator.is_a?(Fluent::GCS::JSONObjectCreator)
    end
  end

  def test_start
    bucket = mock!.bucket("test_bucket") { stub! }

    mock(Google::Cloud::Storage).new(
      project: "test_project",
      keyfile: "test_keyfile",
      retries: 1,
      timeout: 2) { bucket }

    driver = create_driver <<-EOC
      project test_project
      keyfile test_keyfile
      bucket test_bucket
      client_retries 1
      client_timeout 2
      buffer_type memory
    EOC

    driver.instance.start
  end

  def test_ensure_bucket
    bucket = stub!
    bucket.bucket { nil }
    bucket.create_bucket { "ok" }
    stub(Google::Cloud::Storage).new { bucket }

    driver = create_driver <<-EOC
      bucket test_bucket
      buffer_type memory
    EOC
    driver.instance.start
    assert_equal "ok", driver.instance.instance_variable_get(:@gcs_bucket)

    driver2 = create_driver <<-EOC
      bucket test_bucket
      buffer_type memory
      auto_create_bucket false
    EOC
    assert_raise do
      driver2.instance.start
    end
  end

  sub_test_case "foramt" do
    setup do
      bucket = stub!
      bucket.find_file { false }
      bucket.upload_file
      storage = stub!
      storage.bucket { bucket }
      stub(Google::Cloud::Storage).new { storage }

      @time = Time.parse("2016-01-01 12:00:00 UTC").to_i
    end

    def test_format
      driver = create_driver
      driver.emit({"a"=>1}, @time)
      driver.emit({"a"=>2}, @time)
      driver.expect_format %[2016-01-01T12:00:00Z\ttest\t{"a":1}\n]
      driver.expect_format %[2016-01-01T12:00:00Z\ttest\t{"a":2}\n]
      driver.run
    end

    def test_format_included_tag_and_time
      driver = create_driver(config(CONFIG, 'include_tag_key true', 'include_time_key true'))
      driver.emit({"a"=>1}, @time)
      driver.emit({"a"=>2}, @time)
      driver.expect_format %[2016-01-01T12:00:00Z\ttest\t{"a":1,"tag":"test","time":"2016-01-01T12:00:00Z"}\n]
      driver.expect_format %[2016-01-01T12:00:00Z\ttest\t{"a":2,"tag":"test","time":"2016-01-01T12:00:00Z"}\n]
      driver.run
    end

    def test_format_with_format_ltsv
      driver = create_driver(config(CONFIG, 'format ltsv'))
      driver.emit({"a"=>1, "b"=>1}, @time)
      driver.emit({"a"=>2, "b"=>2}, @time)
      driver.expect_format %[a:1\tb:1\n]
      driver.expect_format %[a:2\tb:2\n]
      driver.run
    end

    def test_format_with_format_json
      driver = create_driver(config(CONFIG, 'format json'))
      driver.emit({"a"=>1}, @time)
      driver.emit({"a"=>2}, @time)
      driver.expect_format %[{"a":1}\n]
      driver.expect_format %[{"a":2}\n]
      driver.run
    end

    def test_format_with_format_json_included_tag
      driver = create_driver(config(CONFIG, 'format json', 'include_tag_key true'))
      driver.emit({"a"=>1}, @time)
      driver.emit({"a"=>2}, @time)
      driver.expect_format %[{"a":1,"tag":"test"}\n]
      driver.expect_format %[{"a":2,"tag":"test"}\n]
      driver.run
    end

    def test_format_with_format_json_included_time
      driver = create_driver(config(CONFIG, 'format json', 'include_time_key true'))
      driver.emit({"a"=>1}, @time)
      driver.emit({"a"=>2}, @time)
      driver.expect_format %[{"a":1,"time":"2016-01-01T12:00:00Z"}\n]
      driver.expect_format %[{"a":2,"time":"2016-01-01T12:00:00Z"}\n]
      driver.run
    end

    def test_format_with_format_json_included_tag_and_time
      driver = create_driver(config(CONFIG, 'format json', 'include_tag_key true', 'include_time_key true'))
      driver.emit({"a"=>1}, @time)
      driver.emit({"a"=>2}, @time)
      driver.expect_format %[{"a":1,"tag":"test","time":"2016-01-01T12:00:00Z"}\n]
      driver.expect_format %[{"a":2,"tag":"test","time":"2016-01-01T12:00:00Z"}\n]
      driver.run
    end
  end

  sub_test_case "write" do
    def check_upload(conf, path = nil, enc_opts = nil, upload_opts = nil, &block)
      bucket = mock!
      if block.nil?
        bucket.find_file(path, enc_opts) { false }
        bucket.upload_file(anything, path, upload_opts.merge(enc_opts))
      else
        block.call(bucket)
      end
      storage = stub!
      storage.bucket { bucket }
      stub(Google::Cloud::Storage).new { storage }


      driver = create_driver(conf)
      driver.emit({"a"=>1}, Time.parse("2016-01-01 15:00:00 UTC").to_i)
      driver.run
    end

    def test_write_with_gzip
      conf = config(CONFIG, "store_as gzip")

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {},
        acl: nil,
        content_type: "application/gzip",
        content_encoding: nil,
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      check_upload(conf, "log/20160101_0.gz", enc_opts, upload_opts)
    end

    def test_write_with_transcoding
      conf = config(CONFIG, "store_as gzip", "transcoding true")

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {},
        acl: nil,
        content_type: "text/plain",
        content_encoding: "gzip",
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      check_upload(conf, "log/20160101_0.gz", enc_opts, upload_opts)
    end

    def test_write_with_text
      conf = config(CONFIG, "store_as text")

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {},
        acl: nil,
        content_type: "text/plain",
        content_encoding: nil,
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      check_upload(conf, "log/20160101_0.txt", enc_opts, upload_opts)
    end

    def test_write_with_json
      conf = config(CONFIG, "store_as json")

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {},
        acl: nil,
        content_type: "application/json",
        content_encoding: nil,
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      check_upload(conf, "log/20160101_0.json", enc_opts, upload_opts)
    end

    def test_write_with_localtime
      conf = config(CONFIG.gsub("utc", "localtime"))

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {},
        acl: nil,
        content_type: "application/gzip",
        content_encoding: nil,
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      check_upload(conf, "log/20160102_0.gz", enc_opts, upload_opts)
    end

    def test_write_with_encryption
      conf = config(CONFIG, "encryption_key aaa", "encryption_key_sha256 bbb")

      enc_opts = {
        encryption_key: "aaa",
        encryption_key_sha256: "bbb"
      }

      upload_opts = {
        metadata: {},
        acl: nil,
        content_type: "application/gzip",
        content_encoding: nil,
        encryption_key: "aaa",
        encryption_key_sha256: "bbb"
      }.merge(enc_opts)

      check_upload(conf, "log/20160101_0.gz", enc_opts, upload_opts)
    end

    def test_write_with_acl
      conf = config(CONFIG, "acl auth_read")

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {},
        acl: :auth_read,
        content_type: "application/gzip",
        content_encoding: nil,
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      check_upload(conf, "log/20160101_0.gz", enc_opts, upload_opts)
    end

    def test_write_with_object_metadata
      conf = config(CONFIG, <<-EOM)
        <object_metadata>
          key test-key-1
          value test-value-1
        </object_metadata>
        <object_metadata>
          key test-key-2
          value test-value-2
        </object_metadata>
      EOM

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {"test-key-1" => "test-value-1", "test-key-2" => "test-value-2"},
        acl: nil,
        content_type: "application/gzip",
        content_encoding: nil,
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      check_upload(conf, "log/20160101_0.gz", enc_opts, upload_opts)
    end

    def test_write_with_custom_object_key_format
      conf = config(CONFIG, "object_key_format %{path}%{file_extension}/%{hex_random}/%{index}/%{time_slice}/%{uuid_flush}")

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {},
        acl: nil,
        content_type: "application/gzip",
        content_encoding: nil,
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      any_instance_of(Fluent::MemoryBufferChunk) do |b|
        # Memo: Digest::MD5.hexdigest("unique_id") => "69080cee5b6d4c35a8bbf5c48335fe08"
        stub(b).unique_id { "unique_id" }
      end
      mock(SecureRandom).uuid { "uuid1" }
      mock(SecureRandom).uuid { "uuid2" }

      check_upload(conf) do |bucket|
        bucket.find_file(anything, enc_opts) { true }
        bucket.find_file(anything, enc_opts) { false }
        bucket.upload_file(anything, "log/gz/6908/1/20160101/uuid2", upload_opts.merge(enc_opts))
      end
    end

    def test_write_with_overwrite_true
      conf = config(CONFIG, "object_key_format %{path}%{time_slice}.%{file_extension}", "overwrite true")

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      upload_opts = {
        metadata: {},
        acl: nil,
        content_type: "application/gzip",
        content_encoding: nil,
        encryption_key: nil,
        encryption_key_sha256: nil
      }.merge(enc_opts)

      check_upload(conf) do |bucket|
        bucket.find_file(anything, enc_opts) { true }
        bucket.find_file(anything, enc_opts) { true }
        bucket.upload_file(anything, "log/20160101.gz", upload_opts.merge(enc_opts))
      end
    end

    def test_write_with_overwrite_false
      conf = config(CONFIG, "object_key_format %{path}%{time_slice}.%{file_extension}", "overwrite false")

      enc_opts = {
        encryption_key: nil,
        encryption_key_sha256: nil
      }

      assert_raise do
        check_upload(conf) do |bucket|
          bucket.find_file(anything, enc_opts) { true }
          bucket.find_file(anything, enc_opts) { true }
        end
      end
    end
  end
end
