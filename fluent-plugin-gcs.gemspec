require_relative "lib/fluent/plugin/gcs/version"

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-gcs"
  spec.version       = Fluent::GCSPlugin::VERSION
  spec.authors       = ["Daichi HIRATA"]
  spec.email         = ["hirata.daichi@gmail.com"]
  spec.summary       = "Google Cloud Storage output plugin for Fluentd"
  spec.description   = "Fluentd output plugin that buffers events and uploads them to Google Cloud Storage as gzip, json, or text objects."
  spec.homepage      = "https://github.com/daichirata/fluent-plugin-gcs"
  spec.license       = "Apache-2.0"

  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "source_code_uri"       => spec.homepage,
    "bug_tracker_uri"       => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true",
  }

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "fluentd", ">= 1.0", "< 3"
  spec.add_runtime_dependency "google-cloud-storage", "~> 1.1"
end
