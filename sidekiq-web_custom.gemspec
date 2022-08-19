# frozen_string_literal: true

require_relative "lib/sidekiq/web_custom/version"

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-web_custom"
  spec.version       = Sidekiq::WebCustom::VERSION
  spec.authors       = ["Matt Taylor"]
  spec.email         = ["mattius.taylor@gmail.com"]

  spec.summary       = "This gem adds on custom capabilities to the Sidekiq Web UI"
  spec.description   = <<-DOC
    Have you ever needed to add custom buttons to the sidekiq UI?
    Have you ever needed to drain a queue that is not bound to a Sidekiq Process?
    This Gem allows you to to do all of that from the Sidekiq UI!
  DOC
  spec.homepage      = "https://github.com/matt-taylor/sidekiq-web_custom"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7")

  # spec.metadata["allowed_push_host"] = "Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/matt-taylor/sidekiq-web_custom"
  spec.metadata["changelog_uri"] = "https://github.com/matt-taylor/sidekiq-web_custom/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'sidekiq', '~> 6.5'
  spec.add_dependency 'timeoutable', '>= 1.0'
end
