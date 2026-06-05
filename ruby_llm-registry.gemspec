# frozen_string_literal: true

require_relative "lib/ruby_llm/registry/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_llm-registry"
  spec.version = RubyLLM::Registry::VERSION
  spec.authors = ["Sal Scotto"]
  spec.email = ["sal.scotto@gmail.com"]

  spec.summary = "Production-grade prompt lifecycle management for RubyLLM"
  spec.description = "Local-first, versioned prompt storage and rendering for RubyLLM applications."
  spec.homepage = "https://github.com/washu/ruby_llm-registry"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/washu/ruby_llm-registry/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
