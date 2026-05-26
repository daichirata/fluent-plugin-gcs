require "helper"
require "fluent/test/driver/output"
require "fluent/test/helpers"
require "google/cloud/storage"

class GCSOutputTest < Test::Unit::TestCase
  include Fluent::Test::Helpers

  def setup
    Fluent::Test.setup
  end

  CONFIG = <<-EOC
    project test_project
    keyfile test_keyfile
    bucket test_bucket
    path log/
    <buffer>
      @type memory
      timekey_use_utc true
    </buffer>
    <system>
      log_level debug
    </system>
  EOC

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::GCSOutput) do
      attr_accessor :object_creator, :encryption_opts
    end.configure(conf)
  end

  def config(*args)
    args.join("\n")
  end

  def upload_opts(overrides = {})
    {
      metadata: {},
      acl: nil,
      storage_class: nil,
      content_type: "application/gzip",
      content_encoding: nil,
      encryption_key: nil,
    }.merge(overrides)
  end

  def enc_opts(overrides = {})
    { encryption_key: nil }.merge(overrides)
  end

  def format_section(type)
    "<format>\n  @type #{type}\n</format>"
  end

  def inject_section(*lines)
    (["<inject>"] + lines.map { |l| "  #{l}" } + ["</inject>"]).join("\n")
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
      assert_equal nil, driver.instance.acl
      assert_equal nil, driver.instance.storage_class
      assert_equal nil, driver.instance.encryption_key
      assert_equal [], driver.instance.object_metadata
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
      driver = create_driver(config(CONFIG, "store_as gzip"))
      assert_equal true, driver.instance.object_creator.is_a?(Fluent::GCS::GZipObjectCreator)
    end

    def test_configure_with_text_object_creator
      driver = create_driver(config(CONFIG, "store_as text"))
      assert_equal true, driver.instance.object_creator.is_a?(Fluent::GCS::TextObjectCreator)
    end

    def test_configure_with_json_object_creator
      driver = create_driver(config(CONFIG, "store_as json"))
      assert_equal true, driver.instance.object_creator.is_a?(Fluent::GCS::JSONObjectCreator)
    end

    def test_configure_with_gzip_command_object_creator
      driver = create_driver(config(CONFIG, "store_as gzip_command"))
      assert_equal true, driver.instance.object_creator.is_a?(Fluent::GCS::GZipCommandObjectCreator)
    end

    def test_configure_with_gzip_command_parameter
      driver = create_driver(config(CONFIG, "store_as gzip_command", "gzip_command_parameter -1"))
      assert_equal true, driver.instance.object_creator.is_a?(Fluent::GCS::GZipCommandObjectCreator)
      assert_equal "-1", driver.instance.gzip_command_parameter
    end

    def test_configure_with_credentials_json
      driver = create_driver(<<-EOC)
        bucket test_bucket
        credentials_json {"type":"service_account","project_id":"x"}
        <buffer>
          @type memory
          timekey_use_utc true
        </buffer>
      EOC
      expected = {"type" => "service_account", "project_id" => "x"}
      assert_equal expected, driver.instance.credentials_json
      assert_equal expected, driver.instance.instance_variable_get(:@credentials)
    end

    data(
      "invalid store_as"     => ["store_as", "invalid"],
      "invalid acl"          => ["acl", "invalid"],
      "invalid storage_class" => ["storage_class", "invalid"],
    )
    def test_configure_rejects_invalid_enum(data)
      key, value = data
      assert_raise Fluent::ConfigError do
        create_driver(config(CONFIG, "#{key} #{value}"))
      end
    end

    def test_configure_default_formatter_is_out_file
      driver = create_driver
      assert_kind_of Fluent::Plugin::OutFileFormatter, driver.instance.instance_variable_get(:@formatter)
    end

    def test_configure_format_section_overrides_formatter
      driver = create_driver(config(CONFIG, format_section("json")))
      assert_kind_of Fluent::Plugin::JSONFormatter, driver.instance.instance_variable_get(:@formatter)
    end

    def test_configure_default_buffer_settings
      driver = create_driver
      buffer = driver.instance.buffer_config
      assert_equal ["time"], buffer.chunk_keys
      assert_equal 60 * 60 * 24, buffer.timekey
    end

    def test_configure_object_metadata_section
      driver = create_driver(config(CONFIG, <<-EOM))
        <object_metadata>
          key k1
          value v1
        </object_metadata>
        <object_metadata>
          key k2
          value v2
        </object_metadata>
      EOM
      assert_equal(
        {"k1" => "v1", "k2" => "v2"},
        driver.instance.instance_variable_get(:@object_metadata_hash),
      )
    end
  end

  def test_start
    bucket = mock("bucket")
    storage = mock("storage")
    storage.expects(:bucket).with("test_bucket").returns(bucket)

    Google::Cloud::Storage.expects(:new).with(
      project: "test_project",
      keyfile: "test_keyfile",
      retries: 1,
      timeout: 2,
    ).returns(storage)

    driver = create_driver <<-EOC
      project test_project
      keyfile test_keyfile
      bucket test_bucket
      client_retries 1
      client_timeout 2
      <buffer>
        @type memory
        timekey_use_utc true
      </buffer>
    EOC

    driver.instance.start
  end

  def test_start_with_credentials_json
    bucket = mock("bucket")
    storage = mock("storage")
    storage.expects(:bucket).with("test_bucket").returns(bucket)

    credentials = {"type" => "service_account", "project_id" => "x"}
    Google::Cloud::Storage.expects(:new).with(
      project: nil,
      keyfile: credentials,
      retries: nil,
      timeout: nil,
    ).returns(storage)

    driver = create_driver <<-EOC
      bucket test_bucket
      credentials_json {"type":"service_account","project_id":"x"}
      <buffer>
        @type memory
        timekey_use_utc true
      </buffer>
    EOC

    driver.instance.start
  end

  def test_ensure_bucket
    storage = mock("storage")
    storage.stubs(:bucket).returns(nil)
    storage.stubs(:create_bucket).returns("ok")
    Google::Cloud::Storage.stubs(:new).returns(storage)

    driver = create_driver <<-EOC
      bucket test_bucket
      <buffer>
        @type memory
        timekey_use_utc true
      </buffer>
    EOC
    driver.instance.start
    assert_equal "ok", driver.instance.instance_variable_get(:@gcs_bucket)
  end

  def test_ensure_bucket_raises_when_auto_create_disabled
    storage = mock("storage")
    storage.stubs(:bucket).returns(nil)
    Google::Cloud::Storage.stubs(:new).returns(storage)

    driver = create_driver <<-EOC
      bucket test_bucket
      auto_create_bucket false
      <buffer>
        @type memory
        timekey_use_utc true
      </buffer>
    EOC
    err = assert_raise(RuntimeError) { driver.instance.start }
    assert_equal "bucket `test_bucket` does not exist", err.message
  end

  def test_multi_workers_ready
    driver = create_driver
    assert_equal true, driver.instance.multi_workers_ready?
  end

  sub_test_case "private helpers" do
    def test_timekey_to_timeformat
      driver = create_driver

      assert_equal "", driver.instance.send(:timekey_to_timeformat, nil)
      assert_equal "%Y%m%d%H%M%S", driver.instance.send(:timekey_to_timeformat, 0)
      assert_equal "%Y%m%d%H%M%S", driver.instance.send(:timekey_to_timeformat, 59)
      assert_equal "%Y%m%d%H%M", driver.instance.send(:timekey_to_timeformat, 60)
      assert_equal "%Y%m%d%H%M", driver.instance.send(:timekey_to_timeformat, 3599)
      assert_equal "%Y%m%d%H", driver.instance.send(:timekey_to_timeformat, 3600)
      assert_equal "%Y%m%d%H", driver.instance.send(:timekey_to_timeformat, 86_399)
      assert_equal "%Y%m%d", driver.instance.send(:timekey_to_timeformat, 86_400)
    end

  end

  sub_test_case "foramt" do
    setup do
      bucket = mock("bucket")
      bucket.stubs(:find_file).returns(false)
      bucket.stubs(:upload_file)
      storage = mock("storage")
      storage.stubs(:bucket).returns(bucket)
      Google::Cloud::Storage.stubs(:new).returns(storage)

      @time = event_time("2016-01-01 12:00:00 UTC")
    end

    def test_format
      with_timezone("UTC") do
        driver = create_driver(CONFIG)
        driver.run(default_tag: "test") do
          driver.feed(@time, {"a"=>1})
          driver.feed(@time, {"a"=>2})
        end
        assert_equal %[2016-01-01T12:00:00+00:00\ttest\t{"a":1}\n], driver.formatted[0]
        assert_equal %[2016-01-01T12:00:00+00:00\ttest\t{"a":2}\n], driver.formatted[1]
      end
    end

    def test_format_included_tag_and_time
      with_timezone("UTC") do
        driver = create_driver(config(CONFIG, inject_section("tag_key tag", "time_key time", "time_type string")))
        driver.run(default_tag: "test") do
          driver.feed(@time, {"a"=>1})
          driver.feed(@time, {"a"=>2})
        end
        assert_equal %[2016-01-01T12:00:00+00:00\ttest\t{"a":1,"tag":"test","time":"2016-01-01T12:00:00+00:00"}\n],
                     driver.formatted[0]
        assert_equal %[2016-01-01T12:00:00+00:00\ttest\t{"a":2,"tag":"test","time":"2016-01-01T12:00:00+00:00"}\n],
                     driver.formatted[1]
      end
    end

    def test_format_with_format_ltsv
      with_timezone("UTC") do
        driver = create_driver(config(CONFIG, format_section("ltsv")))
        driver.run(default_tag: "test") do
          driver.feed(@time, {"a"=>1, "b"=>1})
          driver.feed(@time, {"a"=>2, "b"=>2})
        end
        assert_equal %[a:1\tb:1\n], driver.formatted[0]
        assert_equal %[a:2\tb:2\n], driver.formatted[1]
      end
    end

    def test_format_with_format_json
      with_timezone("UTC") do
        driver = create_driver(config(CONFIG, format_section("json")))
        driver.run(default_tag: "test") do
          driver.feed(@time, {"a"=>1})
          driver.feed(@time, {"a"=>2})
        end
        assert_equal %[{"a":1}\n], driver.formatted[0]
        assert_equal %[{"a":2}\n], driver.formatted[1]
      end
    end

    def test_format_with_format_json_included_tag
      with_timezone("UTC") do
        driver = create_driver(config(CONFIG, format_section("json"), inject_section("tag_key tag")))
        driver.run(default_tag: "test") do
          driver.feed(@time, {"a"=>1})
          driver.feed(@time, {"a"=>2})
        end
        assert_equal %[{"a":1,"tag":"test"}\n], driver.formatted[0]
        assert_equal %[{"a":2,"tag":"test"}\n], driver.formatted[1]
      end
    end

    def test_format_with_format_json_included_time
      with_timezone("UTC") do
        driver = create_driver(config(CONFIG, format_section("json"), inject_section("time_key time", "time_type string")))
        driver.run(default_tag: "test") do
          driver.feed(@time, {"a"=>1})
          driver.feed(@time, {"a"=>2})
        end
        assert_equal %[{"a":1,"time":"2016-01-01T12:00:00+00:00"}\n], driver.formatted[0]
        assert_equal %[{"a":2,"time":"2016-01-01T12:00:00+00:00"}\n], driver.formatted[1]
      end
    end

    def test_format_with_format_json_included_tag_and_time
      with_timezone("UTC") do
        driver = create_driver(config(CONFIG, format_section("json"), inject_section("tag_key tag", "time_key time", "time_type string")))
        driver.run(default_tag: "test") do
          driver.feed(@time, {"a"=>1})
          driver.feed(@time, {"a"=>2})
        end
        assert_equal %[{"a":1,"tag":"test","time":"2016-01-01T12:00:00+00:00"}\n], driver.formatted[0]
        assert_equal %[{"a":2,"tag":"test","time":"2016-01-01T12:00:00+00:00"}\n], driver.formatted[1]
      end
    end
  end

  sub_test_case "write" do
    def check_upload(conf, path = nil, enc_opts = nil, upload_opts = nil, &block)
      bucket = mock("bucket")
      if block.nil?
        bucket.expects(:find_file).with(path, **enc_opts).returns(false)
        bucket.expects(:upload_file).with(anything, path, **upload_opts.merge(enc_opts))
      else
        block.call(bucket)
      end
      storage = mock("storage")
      storage.stubs(:bucket).returns(bucket)
      Google::Cloud::Storage.stubs(:new).returns(storage)

      driver = create_driver(conf)
      driver.run(default_tag: "test") do
        driver.feed(event_time("2016-01-01 15:00:00 UTC"), {"a"=>1})
      end
    end

    def test_write_with_gzip
      conf = config(CONFIG, "store_as gzip")
      check_upload(conf, "log/20160101_0.gz", enc_opts, upload_opts)
    end

    def test_write_with_transcoding
      conf = config(CONFIG, "store_as gzip", "transcoding true")
      check_upload(conf, "log/20160101_0.gz", enc_opts,
                   upload_opts(content_type: "text/plain", content_encoding: "gzip"))
    end

    def test_write_with_text
      conf = config(CONFIG, "store_as text")
      check_upload(conf, "log/20160101_0.txt", enc_opts,
                   upload_opts(content_type: "text/plain"))
    end

    def test_write_with_json
      conf = config(CONFIG, "store_as json")
      check_upload(conf, "log/20160101_0.json", enc_opts,
                   upload_opts(content_type: "application/json"))
    end

    def test_write_with_gzip_command
      conf = config(CONFIG, "store_as gzip_command")
      check_upload(conf, "log/20160101_0.gz", enc_opts, upload_opts)
    end

    def test_write_with_gzip_command_and_transcoding
      conf = config(CONFIG, "store_as gzip_command", "transcoding true")
      check_upload(conf, "log/20160101_0.gz", enc_opts,
                   upload_opts(content_type: "text/plain", content_encoding: "gzip"))
    end

    def test_write_with_utc
      conf = config(CONFIG)
      Timecop.freeze(Time.parse("2016-01-02 01:00:00 JST")) do
        check_upload(conf, "log/20160101_0.gz", enc_opts, upload_opts)
      end
    end

    def test_write_with_placeholder_in_path
      conf = <<-CONFIG
        project test_project
        keyfile test_keyfile
        bucket test_bucket
        path log/${tag}/
        <buffer tag,time>
          @type memory
          timekey 86400
          timekey_wait 10m
          timekey_use_utc true
        </buffer>
      CONFIG

      Timecop.freeze(Time.parse("2016-01-02 01:00:00 JST")) do
        check_upload(conf, "log/test/20160101_0.gz", enc_opts, upload_opts)
      end
    end

    def test_write_without_timekey
      conf = <<-CONFIG
        project test_project
        keyfile test_keyfile
        bucket test_bucket
        path log/
        object_key_format %{path}%{time_slice}%{index}.%{file_extension}
        <buffer tag>
          @type memory
        </buffer>
      CONFIG

      check_upload(conf, "log/0.gz", enc_opts, upload_opts)
    end

    def test_write_with_encryption
      conf = config(CONFIG, "encryption_key aaa")
      check_upload(conf, "log/20160101_0.gz",
                   enc_opts(encryption_key: "aaa"),
                   upload_opts(encryption_key: "aaa"))
    end

    def test_write_with_acl
      conf = config(CONFIG, "acl auth_read")
      check_upload(conf, "log/20160101_0.gz", enc_opts,
                   upload_opts(acl: :auth_read))
    end

    def test_write_with_storage_class
      conf = config(CONFIG, "storage_class regional")
      check_upload(conf, "log/20160101_0.gz", enc_opts,
                   upload_opts(storage_class: :regional))
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

      check_upload(conf, "log/20160101_0.gz", enc_opts,
                   upload_opts(metadata: {"test-key-1" => "test-value-1", "test-key-2" => "test-value-2"}))
    end

    def test_write_with_custom_object_key_format
      conf = config(CONFIG, "object_key_format %{path}%{file_extension}/%{hex_random}/%{hostname}/%{index}/%{time_slice}/%{uuid_flush}")

      # Memo: Digest::MD5.hexdigest("unique_id") => "69080cee5b6d4c35a8bbf5c48335fe08"
      Fluent::Plugin::Buffer::MemoryChunk.any_instance.stubs(:unique_id).returns("unique_id")
      SecureRandom.stubs(:uuid).returns("uuid1", "uuid2")
      Socket.stubs(:gethostname).returns("test-hostname")

      check_upload(conf) do |bucket|
        bucket.stubs(:find_file).with(anything, **enc_opts).returns(true).then.returns(false)
        bucket.expects(:upload_file).with(anything, "log/gz/6908/test-hostname/1/20160101/uuid2", **upload_opts.merge(enc_opts))
      end
    end

    def test_write_with_overwrite_true
      conf = config(CONFIG, "object_key_format %{path}%{time_slice}.%{file_extension}", "overwrite true")

      check_upload(conf) do |bucket|
        bucket.stubs(:find_file).with(anything, **enc_opts).returns(true)
        bucket.expects(:upload_file).with(anything, "log/20160101.gz", **upload_opts.merge(enc_opts))
      end
    end

    def test_write_with_overwrite_false
      conf = config(CONFIG, "object_key_format %{path}%{time_slice}.%{file_extension}", "overwrite false")

      err = assert_raise(RuntimeError) do
        silenced do
          check_upload(conf) do |bucket|
            bucket.stubs(:find_file).with(anything, **enc_opts).returns(true)
          end
        end
      end
      assert_equal "object `log/20160101.gz` already exists", err.message
    end

    def test_write_with_blind_write
      conf = config(CONFIG, "blind_write true")

      check_upload(conf) do |bucket|
        bucket.expects(:find_file).never
        bucket.expects(:upload_file).with(anything, "log/20160101_0.gz", **upload_opts.merge(enc_opts))
      end
    end
  end
end
