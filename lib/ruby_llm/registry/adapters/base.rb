# frozen_string_literal: true

module RubyLlm
  module Registry
    module Adapters
      # Shared adapter behavior for prompt storage backends.
      class Base
        def get(_path, version: nil, label: nil)
          raise NotImplementedError, "#{self.class} must implement #get"
        end

        def available_versions(_path)
          []
        end

        def store(_prompt, **)
          raise NotImplementedError, "#{self.class} must implement #store"
        end

        def export(path, version: nil, label: nil, format: :markdown, **options)
          prompt = get(path, version: version, label: label)
          Exporter.new(prompt).public_send(exporter_method(format), **options)
        end

        def import(payload, format: :auto, **options)
          prompt = Importer.new(payload, format: format, **options).to_prompt
          store(prompt)
          prompt
        end

        private

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
end

