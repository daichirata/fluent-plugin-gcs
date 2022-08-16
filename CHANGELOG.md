## [Unreleased]

New features / Enhancements

## [0.4.2] - 2022/08/16

Bug fixes

- [Fix automatic conversion from a hash to keyword arguments](https://github.com/daichirata/fluent-plugin-gcs/pull/22)

## [0.4.1] - 2020/04/17

New features
- [Support blind write to GSC](https://github.com/daichirata/fluent-plugin-gcs/pull/14)

## [0.4.0] - 2019/04/01

New features / Enhancements

- [Support v0.14 (by @cosmo0920)](https://github.com/daichirata/fluent-plugin-gcs/pull/6)

## [0.3.0] - 2017/02/28

New features / Enhancements

- [Add support for setting a File's storage_class on file creation](https://github.com/daichirata/fluent-plugin-gcs/pull/4)
  - see also https://cloud.google.com/storage/docs/storage-classes

## [0.2.0] - 2017/01/16

Bug fixes

- [Remove encryption_key_sha256 parameter.](https://github.com/daichirata/fluent-plugin-gcs/pull/2)
  - see also. https://github.com/GoogleCloudPlatform/google-cloud-ruby/blob/master/google-cloud-storage/CHANGELOG.md#0230--2016-12-8

## [0.1.1] - 2016/11/28

New features / Enhancements

- Add support for `%{hostname}` of object_key_format

[Unreleased]: https://github.com/daichirata/fluent-plugin-gcs/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/daichirata/fluent-plugin-gcs/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/daichirata/fluent-plugin-gcs/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/daichirata/fluent-plugin-gcs/compare/v0.1.0...v0.2.0
[0.1.1]: https://github.com/daichirata/fluent-plugin-gcs/compare/v0.1.0...v0.1.1
