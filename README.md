# fluent-plugin-gcs
<!-- TODO: travis, codeclimate, rubygems -->

Google Cloud Storage output plugin for [Fluentd](https://github.com/fluent/fluentd).

## Installation

``` shell
gem install fluent-plugin-gcs
```

## Examples

```
<match pattern>
  @type gcs

  project YOUR_PROJECT
  keyfile YOUR_KEYFILE_PATH
  gcs_bucket YOUR_GCS_BUCKET_NAME
  gcs_object_key_format %{path}%{time_slice}_%{index}.%{file_extension}
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

to decide keys dynamically.

* `%{path}` is exactly the value of `path` configured in the configuration file. E.g., "logs/" in the example configuration above.
* `%{time_slice}` is the time-slice in text that are formatted with `time_slice_format`.
* `%{index}` is the sequential number starts from 0, increments when multiple files are uploaded to GCS in the same time slice.
* `%{file_extention}` is changed by the value of `store_as`.
  * gzip - gz
  * json - json
  * text - txt
* `%{uuid_flush}` a uuid that is replaced everytime the buffer will be flushed
* `%{hex_random}` a random hex string that is replaced for each buffer chunk, not assured to be unique.
You can configure the length of string with a `hex_random_length` parameter (Default: 4).

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

TODO: rate limit

**acl**

Permission for the object in GCS. Acceptable values are:

* `auth_read`       - File owner gets OWNER access, and allAuthenticatedUsers get READER access.
* `owner_full`      - File owner gets OWNER access, and project team owners get OWNER access.
* `owner_read`      - File owner gets OWNER access, and project team owners get READER access.
* `private`         - File owner gets OWNER access.
* `project_private` - File owner gets OWNER access, and project team members get access according to their roles.
* `public_read`     - File owner gets OWNER access, and allUsers get READER access.

Default is nil (bucket default object ACL). See also [official document](https://cloud.google.com/storage/docs/access-control/lists).

**encryption_key**, **encryption_key_sha256**

You can also choose to provide your own AES-256 key for server-side encryption. See also [Customer-supplied encryption keys](https://cloud.google.com/storage/docs/encryption#customer-supplied).

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
