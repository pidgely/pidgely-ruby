# frozen_string_literal: true

require_relative "lib/pidgely/version"

Gem::Specification.new do |spec|
  spec.name = "pidgely"
  spec.version = Pidgely::VERSION
  spec.authors = ["Caotec Serviços em Tecnologia Ltda"]
  spec.email = ["dev@fexxo.com.br"]
  spec.summary = "Official Ruby SDK for the Pidgely email API (Resend-compatible)."
  spec.description = "Send transactional and broadcast email, manage domains, contacts, segments, templates, " \
                     "webhooks and suppressions with Pidgely. Standard library only, Resend-compatible API."
  spec.homepage = "https://docs.pidgely.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => "https://pidgely.com",
    "documentation_uri" => "https://docs.pidgely.com",
    "source_code_uri" => "https://github.com/pidgely/pidgely-ruby",
    "changelog_uri" => "https://github.com/pidgely/pidgely-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/pidgely/pidgely-ruby/issues"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Standard library only (net/http, json, openssl): no runtime dependencies.
end
