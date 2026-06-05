# frozen_string_literal: true

require "erb"

module RubyLLM
  module Registry
    # Represents a loaded prompt template plus its metadata.
    class Prompt
      attr_reader :name, :namespace, :version, :labels, :metadata, :required_vars, :body, :source_path

      def initialize(name:, namespace:, version:, body:, source_path:, labels: [], metadata: {}, required_vars: [])
        @name = name.to_s
        @namespace = namespace.to_s
        @version = version.is_a?(Version) ? version : Version.parse(version)
        @body = body.to_s
        @source_path = source_path
        @labels = Array(labels).compact.map(&:to_sym)
        @metadata = symbolize_keys(metadata)
        @required_vars = Array(required_vars).compact.map(&:to_sym)
      end

      def path
        [namespace, name].reject(&:empty?).join("/")
      end

      def render(context = nil, **kwargs)
        values = normalize_context(context, kwargs)
        validate_required_vars!(values)
        ERB.new(body, trim_mode: "-").result(RenderContext.new(values).instance_eval { binding })
      end

      def to_message(role: :system, context: nil, **)
        { role: role, content: render(context, **) }
      end

      def export(format: :markdown)
        Exporter.new(self).public_send(exporter_method(format))
      end

      def diff(other)
        other_prompt = other.is_a?(Prompt) ? other : Importer.new(other, format: :auto).to_prompt
        Comparison.new(self, other_prompt)
      end

      def to_h
        {
          path: path,
          namespace: namespace,
          name: name,
          version: version.to_s,
          labels: labels,
          metadata: metadata,
          required_vars: required_vars,
          source_path: source_path,
          body: body
        }
      end

      private

      def normalize_context(context, kwargs)
        if context.is_a?(Hash)
          context.merge(kwargs)
        elsif context.nil?
          kwargs
        elsif kwargs.empty?
          context.respond_to?(:to_h) ? context.to_h : { context: context }
        else
          raise ArgumentError, "Pass either a context hash or keyword arguments, not both"
        end
      end

      def validate_required_vars!(values)
        missing = required_vars.reject { |key| values.key?(key) || values.key?(key.to_s) }
        return if missing.empty?

        raise MissingVariableError, "Missing required prompt variables: #{missing.join(", ")}"
      end

      def symbolize_keys(hash)
        hash.each_with_object({}) do |(key, value), memo|
          memo[key.to_sym] = value
        end
      end

      def exporter_method(format)
        case format.to_sym
        when :yaml then :to_yaml
        when :json then :to_json
        when :markdown, :md then :to_markdown
        when :hash then :to_h
        else
          raise ArgumentError, "Unsupported export format: #{format.inspect}"
        end
      end
    end
  end
end
