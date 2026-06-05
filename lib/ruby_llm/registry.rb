# frozen_string_literal: true

require_relative "registry/version"
require_relative "registry/errors"
require_relative "registry/semver"
require_relative "registry/front_matter"
require_relative "registry/context"
require_relative "registry/prompt"
require_relative "registry/comparison"
require_relative "registry/exporter"
require_relative "registry/importer"
require_relative "registry/adapters"
require_relative "registry/filesystem_backend"

module RubyLlm
  module Registry
    class Configuration
      attr_accessor :root, :manifest_path, :default_adapter, :default_database_adapter

      def initialize
        @root = nil
        @manifest_path = nil
        @default_adapter = :filesystem
        @default_database_adapter = :sqlite
      end
    end

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset!
        @configuration = nil
      end

      def get(path, version: nil, label: nil, root: nil, manifest_path: nil)
        backend(root: root, manifest_path: manifest_path).get(path, version: version, label: label)
      end

      def backend(type = nil, **options)
        type = (type || configuration.default_adapter).to_sym

        case type
        when :filesystem
          FilesystemBackend.new(
            root: options[:root] || configuration.root || default_root,
            manifest_path: options[:manifest_path] || configuration.manifest_path
          )
        when :sqlite, :active_record, :ar, :mongo, :mongodb, :s3
          Adapters.build(type, **options)
        else
          raise ArgumentError, "Unknown backend type: #{type.inspect}"
        end
      end

      def database_backend(type = nil, **options)
        backend(type || configuration.default_database_adapter, **options)
      end

      def export(prompt_or_path, format: :markdown, backend: nil, version: nil, label: nil, **options)
        prompt = if prompt_or_path.is_a?(Prompt)
                   prompt_or_path
                 elsif backend
                   backend.get(prompt_or_path, version: version, label: label)
                 else
                   get(prompt_or_path, version: version, label: label, **options)
                 end
        Exporter.new(prompt).public_send(exporter_method(format))
      end

      def import(payload, format: :auto, backend: nil, **options)
        prompt = Importer.new(payload, format: format, **options).to_prompt
        backend&.store(prompt)
        prompt
      end

      def diff(left, right)
        left_prompt = left.respond_to?(:body) ? left : Importer.new(left, format: :auto).to_prompt
        right_prompt = right.respond_to?(:body) ? right : Importer.new(right, format: :auto).to_prompt
        Comparison.new(left_prompt, right_prompt)
      end

      def default_root
        local_candidates = %w[prompts app/prompts].map { |relative| File.join(Dir.pwd, relative) }
        local_candidates.find { |candidate| Dir.exist?(candidate) } || File.join(Dir.pwd, "prompts")
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
