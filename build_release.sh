#!/bin/bash
set -e

# Extract version from version.rb
VERSION=$(ruby -r ./lib/ruby_llm/registry/version.rb -e "puts RubyLLM::Registry::VERSION")

echo "Building gem version ${VERSION}..."
gem build ruby_llm-registry.gemspec

echo "Pushing to RubyGems..."
gem push ruby_llm-registry-${VERSION}.gem

echo "Done!"
