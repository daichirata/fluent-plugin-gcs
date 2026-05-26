# fluent-plugin-gcs

[![Test](https://github.com/daichirata/fluent-plugin-gcs/actions/workflows/test.yml/badge.svg)](https://github.com/daichirata/fluent-plugin-gcs/actions/workflows/test.yml)
[![Gem Version](https://badge.fury.io/rb/fluent-plugin-gcs.svg)](https://badge.fury.io/rb/fluent-plugin-gcs)

A [Fluentd](https://www.fluentd.org/) output plugin that buffers events and uploads them to [Google Cloud Storage](https://cloud.google.com/storage).

## Features

- **Multiple formats** — store objects as gzip, plain text, or JSON.
- **Fast compression** — optionally shell out to the external `gzip` binary, with automatic fallback to the pure-Ruby compressor.
- **Flexible object keys** — build paths from time slices, tags, hostnames, random tokens, and UUIDs.
- **Server-side controls** — set ACLs, storage class, customer-supplied encryption keys, and custom object metadata.
- **Flexible auth** — explicit credentials or Application Default Credentials on GCE / GKE / Cloud Run.

## Table of contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
  - [Authentication](#authentication)
  - [Object placement](#object-placement)
  - [Format and compression](#format-and-compression)
  - [GCS object settings](#gcs-object-settings)
  - [Object key format](#object-key-format)
  - [Object metadata](#object-metadata)
- [Examples](#examples)
- [Development](#development)
- [Author](#author)
- [License](#license)

## Requirements

| fluent-plugin-gcs | fluentd  | ruby   |
|-------------------|----------|--------|
| >= 0.5.0          | >= 1.0   | >= 3.3 |

## Installation

```shell
gem install fluent-plugin-gcs
```

Using td-agent / fluent-package:

```shell
fluent-gem install fluent-plugin-gcs
```

## Quick start

The minimal configuration needs only a bucket. On GCE, GKE, or Cloud Run the credentials are picked up automatically from the environment.

```aconf
<match your.tag>
  @type gcs

  bucket YOUR_GCS_BUCKET_NAME
  path logs/

  <buffer time>
    @type file
    path /var/log/fluent/gcs
    timekey 1h
    timekey_wait 10m
    timekey_use_utc true
  </buffer>
</match>
```

This writes gzip-compressed objects such as `logs/2024010112_0.gz`, one per hourly time slice.

## Configuration

### Authentication

Provide credentials explicitly, or rely on [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials) when running on Google Cloud.

| Option             | Type    | Default | Description |
|--------------------|---------|---------|-------------|
| `project`          | string  | `nil`   | GCS project identifier |
| `keyfile`          | string  | `nil`   | Path to a service account credentials JSON file |
| `credentials_json` | hash    | `nil`   | Service account credentials inline as JSON. Takes precedence over `keyfile` |
| `client_retries`   | integer | `nil`   | Number of retries on server error |
| `client_timeout`   | integer | `nil`   | Request timeout in seconds |

`project` is resolved in the following order: the `project` option, then the `STORAGE_PROJECT` / `GOOGLE_CLOUD_PROJECT` / `GCLOUD_PROJECT` environment variables, then GCE metadata.

`keyfile` is resolved in the following order: the `keyfile` option, the `GOOGLE_CLOUD_KEYFILE` / `GCLOUD_KEYFILE` (path) or `GOOGLE_CLOUD_KEYFILE_JSON` / `GCLOUD_KEYFILE_JSON` (inline) environment variables, the Cloud SDK's well-known path, then GCE metadata.

### Object placement

| Option              | Type    | Default | Description |
|---------------------|---------|---------|-------------|
| `bucket`            | string  | —       | **Required.** GCS bucket name |
| `path`              | string  | `""`    | Path prefix for objects |
| `object_key_format` | string  | `%{path}%{time_slice}_%{index}.%{file_extension}` | Template for object keys. See [Object key format](#object-key-format) |
| `hex_random_length` | integer | `4`     | Length of the `%{hex_random}` placeholder (max 32) |
| `overwrite`         | bool    | `false` | Overwrite the existing object instead of incrementing `%{index}` |
| `blind_write`       | bool    | `false` | Skip the existence check before writing (see below) |

**Avoiding key collisions.** When `object_key_format` contains `%{index}` (the default), the plugin checks GCS for an existing object and increments `%{index}` until it finds an unused key, so existing objects are never overwritten. This existence check requires the `storage.objects.get` permission.

**`blind_write`** skips that existence check, so the `storage.objects.get` permission is no longer needed. The trade-off is that `%{index}` stops working (it always stays `0`), so you must keep keys unique another way, with `%{hex_random}` (unique per chunk) or `%{uuid_flush}` (unique per flush).

> [!WARNING]
> If a key collides with an existing object (which can happen with `blind_write true`, or with `overwrite true`), uploading it overwrites the existing object, and GCS requires the `storage.objects.delete` permission to do so. Without that permission the flush fails repeatedly and the buffer chunk is eventually lost. With `blind_write true`, include `%{hex_random}` or `%{uuid_flush}` in `object_key_format` to avoid collisions.

### Format and compression

| Option                   | Type   | Default     | Description |
|--------------------------|--------|-------------|-------------|
| `store_as`               | enum   | `gzip`      | Object format: `gzip`, `gzip_command`, `json`, or `text` |
| `gzip_command_parameter` | string | `""`        | Extra arguments for the external `gzip` (only with `store_as gzip_command`) |
| `transcoding`            | bool   | `false`     | Enable [decompressive transcoding](https://cloud.google.com/storage/docs/transcoding) |

| `store_as`     | Description                                                                 | Extension |
|----------------|-----------------------------------------------------------------------------|-----------|
| `gzip`         | Compress with Ruby's built-in `Zlib::GzipWriter`                            | `gz`      |
| `gzip_command` | Compress with the external `gzip`. Faster for large chunks, falls back to `Zlib::GzipWriter` on failure | `gz` |
| `json`         | Upload as `application/json`                                                | `json`    |
| `text`         | Upload as `text/plain`                                                      | `txt`     |

`gzip_command_parameter` is parsed with `shellsplit`, so the value is **not** evaluated by a shell. For example `-1` selects fast compression and `-9` selects best compression.

The per-line format is configured with a `<format>` section (default `out_file`):

```aconf
<format>
  @type json
</format>
```

See the [Formatter documentation](https://docs.fluentd.org/formatter) for available types (`out_file`, `json`, `ltsv`, `single_value`, ...).

### GCS object settings

| Option               | Type   | Default | Description |
|----------------------|--------|---------|-------------|
| `auto_create_bucket` | bool   | `true`  | Create the bucket if it does not exist |
| `acl`                | enum   | `nil`   | Predefined ACL for uploaded objects (see below) |
| `storage_class`      | enum   | `nil`   | Storage class for uploaded objects (see below) |
| `encryption_key`     | string | `nil`   | Customer-supplied AES-256 key for server-side encryption |

**`acl`** accepts one of `auth_read`, `owner_full`, `owner_read`, `private`, `project_private`, `public_read`. Defaults to the bucket's default object ACL. See the [access control documentation](https://cloud.google.com/storage/docs/access-control/lists).

**`storage_class`** accepts one of `dra`, `nearline`, `coldline`, `multi_regional`, `regional`, `standard`. See the [storage classes documentation](https://cloud.google.com/storage/docs/storage-classes).

**`encryption_key`** enables [customer-supplied encryption](https://cloud.google.com/storage/docs/encryption#customer-supplied); the `encryption_key_sha256` is computed automatically.

### Object key format

`object_key_format` supports the following placeholders:

| Placeholder         | Description |
|---------------------|-------------|
| `%{path}`           | The value of the `path` option |
| `%{time_slice}`     | Time slice text derived from the `<buffer>` `timekey` |
| `%{index}`          | Sequential number (from 0) within the same time slice |
| `%{file_extension}` | Inferred from `store_as` (`gz` / `json` / `txt`) |
| `%{uuid_flush}`     | A UUID generated on every buffer flush |
| `%{hex_random}`     | A random hex string per chunk, length set by `hex_random_length` |
| `%{hostname}`       | The hostname of the running server |

The default is `%{path}%{time_slice}_%{index}.%{file_extension}`.

### Object metadata

Attach arbitrary `x-goog-meta-*` headers to uploaded objects with one or more `<object_metadata>` sections:

```aconf
<object_metadata>
  key KEY_1
  value VALUE_1
</object_metadata>

<object_metadata>
  key KEY_2
  value VALUE_2
</object_metadata>
```

## Examples

### Partition by tag and date

```aconf
<match app.**>
  @type gcs

  project YOUR_PROJECT
  bucket YOUR_GCS_BUCKET_NAME
  object_key_format %{path}%{time_slice}/%{hostname}_%{index}.%{file_extension}
  path logs/${tag}/

  <buffer tag,time>
    @type file
    path /var/log/fluent/gcs
    timekey 1d
    timekey_wait 10m
    timekey_use_utc true
  </buffer>

  <format>
    @type json
  </format>
</match>
```

For the tag `app.web` on host `web1`, this writes objects such as `logs/app.web/20240101/web1_0.gz`.

### Fine-grained 1-minute partitions

When `timekey` is under an hour, `%{time_slice}` automatically resolves to minute granularity (`%Y%m%d%H%M`). Add `%{hex_random}` so that multiple flushes within the same minute never collide.

```aconf
<match app.**>
  @type gcs

  bucket YOUR_GCS_BUCKET_NAME
  path logs/
  object_key_format %{path}%{time_slice}_%{hex_random}.%{file_extension}

  <buffer time>
    @type file
    path /var/log/fluent/gcs
    timekey 1m          # 1 minute partition
    timekey_wait 10s    # short wait for late events
    timekey_use_utc true
  </buffer>
</match>
```

This writes objects such as `logs/202401011230_a1b2.gz`, one (or more) per minute.

### Fast compression with the external gzip

```aconf
<match app.**>
  @type gcs

  bucket YOUR_GCS_BUCKET_NAME
  path logs/
  store_as gzip_command
  gzip_command_parameter -1

  <buffer time>
    @type file
    path /var/log/fluent/gcs
    timekey 1h
    timekey_wait 10m
  </buffer>
</match>
```

Using the default `object_key_format`, this writes objects such as `logs/2024010112_0.gz`, one per hourly slice.

### Cost-optimized cold storage

```aconf
<match archive.**>
  @type gcs

  bucket YOUR_GCS_BUCKET_NAME
  path archive/
  storage_class coldline
  acl project_private

  <buffer time>
    @type file
    path /var/log/fluent/gcs-archive
    timekey 1d
    timekey_wait 1h
  </buffer>
</match>
```

Using the default `object_key_format`, this writes objects such as `archive/20240101_0.gz`, one per day, stored in the Coldline class.

## Development

```shell
bundle install
bundle exec rake test                       # run the test suite
bundle exec bundler-audit check --update    # audit dependencies
gem build fluent-plugin-gcs.gemspec         # build the gem
```

## Author

Daichi HIRATA

## License

Apache License 2.0. See [LICENSE.txt](LICENSE.txt).
