# fluent-plugin-gcs
[![Gem Version](https://badge.fury.io/rb/fluent-plugin-gcs.svg)](https://badge.fury.io/rb/fluent-plugin-gcs) [![Test](https://github.com/daichirata/fluent-plugin-gcs/actions/workflows/test.yaml/badge.svg)](https://github.com/daichirata/fluent-plugin-gcs/actions/workflows/test.yaml) [![Code Climate](https://codeclimate.com/github/daichirata/fluent-plugin-gcs/badges/gpa.svg)](https://codeclimate.com/github/daichirata/fluent-plugin-gcs)

Google Cloud Storage output plugin for [Fluentd](https://github.com/fluent/fluentd).

## Requirements

| fluent-plugin-gcs  | fluentd    | ruby   |
|--------------------|------------|--------|
| >= 0.4.0           | >= v0.14.0 | >= 2.4 |
|  < 0.4.0           | >= v0.12.0 | >= 1.9 |

## Installation

``` shell
$ gem install fluent-plugin-gcs -v "~> 0.3" --no-document # for fluentd v0.12 or later
$ gem install fluent-plugin-gcs -v "0.4.0" --no-document # for fluentd v0.14 or later
```

## Examples

### For v0.14 style

```
<match pattern>
  @type gcs

  project YOUR_PROJECT
  keyfile YOUR_KEYFILE_PATH
  bucket YOUR_GCS_BUCKET_NAME
  object_key_format %{path}%{time_slice}_%{index}.%{file_extension}
  path logs/${tag}/%Y/%m/%d/

  # if you want to use ${tag} or %Y/%m/%d/ like syntax in path / object_key_format,
  # need to specify tag for ${tag} and time for %Y/%m/%d in <buffer> argument.
  <buffer tag,time>
    @type file
    path /var/log/fluent/gcs
    timekey 1h # 1 hour partition
    timekey_wait 10m
    timekey_use_utc true # use utc
  </buffer>

  <format>
    @type json
  </format>
</match>
```

### For v0.12 style

```
<match pattern>
  @type gcs

  project YOUR_PROJECT
  keyfile YOUR_KEYFILE_PATH
  bucket YOUR_GCS_BUCKET_NAME
  object_key_format %{path}%{time_slice}_%{index}.%{file_extension}
  path logs/
  buffer_path /var/log/fluent/gcs

  time_slice_format %Y%m%d-%H
  time_slice_wait 10m
  utc
</match>
```

## Configuration

### Authentication

You can provide the project and credential information to connect to the Storage
service, or if you are running on Google Compute Engine this configuration is taken care of for you.

**project**

Project identifier for GCS. Project are discovered in the following order:
* Specify project in `project`
* Discover project in environment variables `STORAGE_PROJECT`, `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`
* Discover GCE credentials

**keyfile**

Path of GCS service account credentials JSON file. Credentials are discovered in the following order:
* Specify credentials path in `keyfile`
* Discover credentials path in environment variables `GOOGLE_CLOUD_KEYFILE`, `GCLOUD_KEYFILE`
* Discover credentials JSON in environment variables `GOOGLE_CLOUD_KEYFILE_JSON`, `GCLOUD_KEYFILE_JSON`
* Discover credentials file in the Cloud SDK's path
* Discover GCE credentials

**client_retries**

Number of times to retry requests on server error.

**client_timeout**

Default timeout to use in requests.

**bucket (*required)**

GCS bucket name.

**store_as**

Archive format on GCS. You can use serveral format:

* gzip (default)
* json
* text

**path**

path prefix of the files on GCS. Default is "" (no prefix).

**object_key_format**

The format of GCS object keys. You can use several built-in variables:

* %{path}
* %{time_slice}
* %{index}
* %{file_extension}
* %{uuid_flush}
* %{hex_random}
* %{hostname}

to decide keys dynamically.

* `%{path}` is exactly the value of `path` configured in the configuration file. E.g., "logs/" in the example configuration above.
* `%{time_slice}` is the time-slice in text that are formatted with `time_slice_format`.
* `%{index}` is the sequential number starts from 0, increments when multiple files are uploaded to GCS in the same time slice.
* `%{file_extention}` is changed by the value of `store_as`.
  * gzip - gz
  * json - json
  * text - txt
* `%{uuid_flush}` a uuid that is replaced everytime the buffer will be flushed
* `%{hex_random}` a random hex string that is replaced for each buffer chunk, not assured to be unique. You can configure the length of string with a `hex_random_length` parameter (Default: 4).
* `%{hostname}` is set to the standard host name of the system of the running server.

The default format is `%{path}%{time_slice}_%{index}.%{file_extension}`.

**hex_random_length**

The length of `%{hex_random}` placeholder.

**transcoding**

Enable the decompressive form of transcoding.

See also [Transcoding of gzip-compressed files](https://cloud.google.com/storage/docs/transcoding).

**format**

Change one line format in the GCS object. You can use serveral format:

* out_file (default)
* json
* ltsv
* single_value

See also [official Formatter article](http://docs.fluentd.org/articles/formatter-plugin-overview).

**auto_create_bucket**

Create GCS bucket if it does not exists. Default is true.

**acl**

Permission for the object in GCS. Acceptable values are:

* `auth_read`       - File owner gets OWNER access, and allAuthenticatedUsers get READER access.
* `owner_full`      - File owner gets OWNER access, and project team owners get OWNER access.
* `owner_read`      - File owner gets OWNER access, and project team owners get READER access.
* `private`         - File owner gets OWNER access.
* `project_private` - File owner gets OWNER access, and project team members get access according to their roles.
* `public_read`     - File owner gets OWNER access, and allUsers get READER access.

Default is nil (bucket default object ACL). See also [official document](https://cloud.google.com/storage/docs/access-control/lists).

**storage_class**

Storage class of the file. Acceptable values are:

* `dra`            - Durable Reduced Availability
* `nearline`       - Nearline Storage
* `coldline`       - Coldline Storage
* `multi_regional` - Multi-Regional Storage
* `regional`       - Regional Storage
* `standard`       - Standard Storage

Default is nil. See also [official document](https://cloud.google.com/storage/docs/storage-classes).

**encryption_key**

You can also choose to provide your own AES-256 key for server-side encryption. See also [Customer-supplied encryption keys](https://cloud.google.com/storage/docs/encryption#customer-supplied).

`encryption_key_sha256` will be calculated using encryption_key.

**overwrite**

Overwrite already existing path. Default is false, which raises an error
if a GCS object of the same path already exists, or increment the
`%{index}` placeholder until finding an absent path.

**buffer_path (*required)**

path prefix of the files to buffer logs.

**time_slice_format**

Format of the time used as the file name. Default is '%Y%m%d'. Use
'%Y%m%d%H' to split files hourly.

**time_slice_wait**

The time to wait old logs. Default is 10 minutes. Specify larger value if
old logs may reache.

**localtime**

Use Local time instead of UTC.

**utc**

Use UTC instead of local time.

And see [official Time Sliced Output article](http://docs.fluentd.org/articles/output-plugin-overview#time-sliced-output-parameters)

**blind_write**

Doesn't check if an object exists in GCS before writing. Default is false.

Allows to avoid granting of `storage.objects.get` permission.

Warning! If the object exists and `storage.objects.delete` permission is not
granted, it will result in an unrecoverable error. Usage of `%{hex_random}` is
recommended.

### ObjectMetadata

User provided web-safe keys and arbitrary string values that will returned with requests for the file as "x-goog-meta-" response headers.

```
<match *>
  @type gcs

  <object_metadata>
    key KEY_DATA_1
    value VALUE_DATA_1
  </object_metadata>

  <object_metadata>
    key KEY_DATA_2
    value VALUE_DATA_2
  </object_metadata>
</match>
```
