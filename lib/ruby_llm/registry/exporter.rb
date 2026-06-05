# frozen_string_literal: true

require "json"
require "yaml"

module RubyLLM
  module Registry
    # Serializes prompt objects into portable formats.
    class Exporter
      def initialize(prompt)
        @prompt = prompt
      end

      def to_h
        prompt.to_h
      end

      def to_yaml
        YAML.dump(to_h)
      end

      def to_json(*args)
        JSON.pretty_generate(to_h, *args)
      end

      def to_markdown
        <<~MARKDOWN.chomp
          ---
          #{YAML.dump(front_matter).sub(/\A---\s*\n/, "").sub(/\n\z/, "")}
          ---

          #{prompt.body}
        MARKDOWN
      end

      private

      attr_reader :prompt

      def front_matter
        {
          version: prompt.version.to_s,
          labels: prompt.labels,
          required_vars: prompt.required_vars,
          metadata: prompt.metadata,
          name: prompt.name,
          namespace: prompt.namespace,
          source_path: prompt.source_path
        }
      end
    end
  end
end

