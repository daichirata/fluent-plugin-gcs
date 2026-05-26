# fluent-plugin-gcs

[![Test](https://github.com/daichirata/fluent-plugin-gcs/actions/workflows/test.yml/badge.svg)](https://github.com/daichirata/fluent-plugin-gcs/actions/workflows/test.yml)
[![Gem Version](https://badge.fury.io/rb/fluent-plugin-gcs.svg)](https://badge.fury.io/rb/fluent-plugin-gcs)

Google Cloud Storage output plugin for [Fluentd](https://github.com/fluent/fluentd).

## Table of contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Example](#example)
- [Configuration](#configuration)
  - [Authentication](#authentication)
  - [Bucket and object placement](#bucket-and-object-placement)
  - [Storage format](#storage-format)
  - [Server-side options](#server-side-options)
  - [Object metadata](#object-metadata)
- [Development](#development)
- [Author](#author)
- [License](#license)

## Requirements

| fluent-plugin-gcs | fluentd     | ruby   |
|-------------------|-------------|--------|
| >= 0.4.5          | >= 0.14.22  | >= 3.3 |
| >= 0.4.0          | >= 0.14.22  | >= 2.4 |
| <  0.4.0          | >= 0.12.0   | >= 1.9 |

## Installation

```shell
gem install fluent-plugin-gcs
```

If you use td-agent or fluent-package:

```shell
fluent-gem install fluent-plugin-gcs
```

## Example

```aconf
<match pattern>
  @type gcs

  project YOUR_PROJECT
  keyfile YOUR_KEYFILE_PATH
  bucket YOUR_GCS_BUCKET_NAME
  object_key_format %{path}%{time_slice}_%{index}.%{file_extension}
  path logs/${tag}/%Y/%m/%d/

  # If you want to use ${tag} or %Y/%m/%d/ in path / object_key_format,
  # specify the corresponding chunk keys in the <buffer> argument.
  <buffer tag,time>
    @type file
    path /var/log/fluent/gcs
    timekey 1h           # 1 hour partition
    timekey_wait 10m
    timekey_use_utc true
  </buffer>

  <format>
    @type json
  </format>
</match>
```

## Configuration

### Authentication

Provide the project and credentials explicitly, or rely on the
Application Default Credentials when running on Google Compute Engine,
GKE, or Cloud Run.

#### project

Project identifier for GCS. Project is discovered in the following order:

* `project` setting
* Environment variables `STORAGE_PROJECT`, `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`
* GCE metadata

#### keyfile

Path of GCS service account credentials JSON file. Credentials are discovered in the following order:

* `keyfile` setting
* Environment variables `GOOGLE_CLOUD_KEYFILE`, `GCLOUD_KEYFILE`
* Environment variables `GOOGLE_CLOUD_KEYFILE_JSON`, `GCLOUD_KEYFILE_JSON`
* The Cloud SDK's well-known credentials path
* GCE metadata

#### credentials_json

GCS service account credentials in JSON form. Takes precedence over `keyfile` when both are set. Marked as a secret so it is not logged.

```aconf
credentials_json {"type": "service_account", "project_id": "...", ...}
```

#### client_retries

Number of times to retry requests on server error.

#### client_timeout

Default timeout (seconds) used for requests.

### Bucket and object placement

#### bucket (required)

GCS bucket name.

#### path

Path prefix of the files on GCS. Default is `""` (no prefix).

#### object_key_format

The format of GCS object keys. The default is `%{path}%{time_slice}_%{index}.%{file_extension}`.

Available placeholders:

| Placeholder        | Description |
|--------------------|-------------|
| `%{path}`          | The value of `path` |
| `%{time_slice}`    | The time slice text formatted based on the `<buffer>` `timekey` |
| `%{index}`         | Sequential number starting from 0, increments when multiple files are uploaded in the same time slice |
| `%{file_extension}` | Inferred from `store_as` (`gz` for gzip / gzip_command, `json` for json, `txt` for text) |
| `%{uuid_flush}`    | A UUID generated each time the buffer is flushed |
| `%{hex_random}`    | A random hex string generated for each buffer chunk. Configurable via `hex_random_length` (default: 4) |
| `%{hostname}`      | The hostname of the running server |

#### hex_random_length

Length of the `%{hex_random}` placeholder. Max 32.

#### overwrite

Overwrite the existing object at the resolved path. Default is `false`, which raises an error if an object of the same path already exists, or increments `%{index}` until finding an unused path.

#### blind_write

Skip checking whether the object exists in GCS before writing. Default is `false`.

Useful when you do not want to grant `storage.objects.get` permission.

> **Warning**
> If the object already exists and `storage.objects.delete` is not granted either, you get an unrecoverable error. Use `%{hex_random}` or `%{uuid_flush}` to keep object keys unique.

### Storage format

#### store_as

Archive format on GCS. Default is `gzip`.

| Value           | Description |
|-----------------|-------------|
| `gzip`          | Compress with the Ruby built-in `Zlib::GzipWriter` |
| `gzip_command`  | Compress with an external `gzip` command. Faster for large chunks. Falls back to `Zlib::GzipWriter` if the command fails |
| `json`          | Upload as `application/json` |
| `text`          | Upload as `text/plain` |

#### gzip_command_parameter

Additional parameters passed to the external `gzip` command when `store_as` is `gzip_command`. Parsed with `shellsplit`, so the value is **not** evaluated by a shell. Default is `""`.

Examples:

* `-1` for fast compression
* `-9` for best compression

```aconf
<match pattern>
  @type gcs
  store_as gzip_command
  gzip_command_parameter -1
  ...
</match>
```

#### transcoding

Enable the decompressive form of transcoding. See [Transcoding of gzip-compressed files](https://cloud.google.com/storage/docs/transcoding).

#### format

Per-line format inside the uploaded object. Default is `out_file`. Common values:

* `out_file` (default)
* `json`
* `ltsv`
* `single_value`

See the [official Formatter documentation](https://docs.fluentd.org/formatter).

### Server-side options

#### auto_create_bucket

Create the GCS bucket if it does not exist. Default is `true`.

#### acl

Permission for the uploaded object. Acceptable values:

| Value             | Description |
|-------------------|-------------|
| `auth_read`       | File owner gets OWNER access, and allAuthenticatedUsers get READER access |
| `owner_full`      | File owner gets OWNER access, and project team owners get OWNER access |
| `owner_read`      | File owner gets OWNER access, and project team owners get READER access |
| `private`         | File owner gets OWNER access |
| `project_private` | File owner gets OWNER access, and project team members get access according to their roles |
| `public_read`     | File owner gets OWNER access, and allUsers get READER access |

Default is `nil` (bucket default object ACL). See the [GCS access control documentation](https://cloud.google.com/storage/docs/access-control/lists).

#### storage_class

Storage class of the uploaded object. Acceptable values:

| Value            | Description |
|------------------|-------------|
| `dra`            | Durable Reduced Availability |
| `nearline`       | Nearline Storage |
| `coldline`       | Coldline Storage |
| `multi_regional` | Multi-Regional Storage |
| `regional`       | Regional Storage |
| `standard`       | Standard Storage |

Default is `nil`. See the [GCS storage classes documentation](https://cloud.google.com/storage/docs/storage-classes).

#### encryption_key

Customer-supplied AES-256 key for server-side encryption. `encryption_key_sha256` is computed automatically. See [Customer-supplied encryption keys](https://cloud.google.com/storage/docs/encryption#customer-supplied).

### Object metadata

User-supplied web-safe keys and values that are returned with object requests as `x-goog-meta-*` response headers.

```aconf
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

## Development

```shell
bundle install
bundle exec rake test
bundle exec bundler-audit check --update
gem build fluent-plugin-gcs.gemspec
```

## Author

Daichi HIRATA

## License

Apache License 2.0. See [LICENSE.txt](LICENSE.txt).
