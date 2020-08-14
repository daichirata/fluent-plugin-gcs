# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fluent/plugin/gcs/version'

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-gcs"
  spec.version       = Fluent::GCSPlugin::VERSION
  spec.authors       = ["Daichi HIRATA", "Bohdan Snisar"]
  spec.email         = ["hirata.daichi@gmail.com", "bogdan.sns@gmail.com"]
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

  spec.add_runtime_dependency "fluentd", "~> 0.12.0"
  spec.add_runtime_dependency "google-cloud-storage", "~> 0.23.2"
  spec.add_runtime_dependency 'lzo', '~> 0.1.0'

  spec.add_development_dependency "bundler", "~> 2.0.1"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rr", "= 1.1.2"
  spec.add_development_dependency "test-unit", ">= 3.0.8"
  spec.add_development_dependency "test-unit-rr", ">= 1.0.3"
  spec.add_development_dependency "timecop"
end
