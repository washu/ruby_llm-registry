# frozen_string_literal: true

require "date"
require "yaml"

module RubyLLM
  module Registry
    # Simple YAML front matter parser for prompt files.
    module FrontMatter
      module_function

      def parse(content)
        return [{}, content] unless content.start_with?("---\n")

        parts = content.split("\n---\n", 2)
        return [{}, content] if parts.length != 2

        header = parts.first.sub(/\A---\n/, "")
        body = parts.last
        metadata = YAML.safe_load(header, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
        metadata = metadata.each_with_object({}) { |(key, value), hash| hash[key.to_sym] = value }
        [metadata, body]
      rescue Psych::SyntaxError
        [{}, content]
      end
    end
  end
end
