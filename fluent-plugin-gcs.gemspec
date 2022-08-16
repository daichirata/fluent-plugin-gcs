# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fluent/plugin/gcs/version'

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-gcs"
  spec.version       = Fluent::GCSPlugin::VERSION
  spec.authors       = ["Daichi HIRATA"]
  spec.email         = ["hirata.daichi@gmail.com"]
  spec.summary       = "Google Cloud Storage output plugin for Fluentd"
  spec.description   = "Google Cloud Storage output plugin for Fluentd"
  spec.homepage      = "https://github.com/daichirata/fluent-plugin-gcs"
  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "fluentd", [">= 0.14.22", "< 2"]
  spec.add_runtime_dependency "google-cloud-storage", "~> 1.1"
end
