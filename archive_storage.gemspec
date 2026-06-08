# frozen_string_literal: true

require_relative "lib/archive_storage/version"

Gem::Specification.new do |spec|
  spec.name = "archive_storage"
  spec.version = ArchiveStorage::VERSION
  spec.authors = ["E. Tashkovyan"]
  spec.email = []

  spec.summary = "Archival storage for Rails uploaders."
  spec.description = "Move older Rails uploads across storage backends such as filesystem, NFS, MinIO, and S3."
  spec.homepage = "https://github.com/estashkovyan/archive_storage"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "lib/**/*",
      "LICENSE.txt",
      "README.md",
      "archive_storage.gemspec"
    ]
  end
  spec.bindir = "exe"
  spec.require_paths = ["lib"]

  spec.add_dependency "activejob", ">= 6.1", "< 9.0"
  spec.add_dependency "activerecord", ">= 6.1", "< 9.0"
  spec.add_dependency "activesupport", ">= 6.1", "< 9.0"
  spec.add_dependency "railties", ">= 6.1", "< 9.0"

  spec.add_development_dependency "aws-sdk-s3", "~> 1"
  spec.add_development_dependency "carrierwave", ">= 2.2", "< 4.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
