# frozen_string_literal: true

require "date"
require "json"
require "yaml"

module RubyLlm
  module Registry
    # Deserializes prompt exports into Prompt objects.
    class Importer
      def initialize(payload, format: :auto, path: nil)
        @payload = payload
        @format = format
        @path = path
      end

      def to_prompt
        data, body = case normalized_format
                     when :hash
                       extract_hash(payload)
                     when :json
                       extract_json(payload)
                     when :yaml
                       extract_yaml(payload)
                     when :markdown
                       extract_markdown(payload)
                     else
                       infer_payload
                     end

        build_prompt(data, body)
      end

      private

      attr_reader :payload, :format, :path

      def normalized_format
        format == :auto ? infer_format : format.to_sym
      end

      def infer_format
        return :hash if payload.is_a?(Hash)
        return :markdown if payload.to_s.start_with?("---\n")
        return :json if payload.to_s.lstrip.start_with?("{")

        :yaml
      end

      def infer_payload
        case infer_format
        when :hash then extract_hash(payload)
        when :markdown then extract_markdown(payload)
        when :json then extract_json(payload)
        else extract_yaml(payload)
        end
      end

      def extract_hash(value)
        data = value.transform_keys(&:to_sym)
        [data, data[:body] || ""]
      end

      def extract_json(value)
        data = JSON.parse(value.to_s)
        extract_hash(data)
      end

      def extract_yaml(value)
        data = YAML.safe_load(value.to_s, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
        extract_hash(data)
      end

      def extract_markdown(value)
        data, body = FrontMatter.parse(value.to_s)
        [data, body]
      end

      def build_prompt(data, body)
        prompt_path = path || data[:path] || data["path"]
        namespace, name = split_path(prompt_path, data)
        Prompt.new(
          name: name,
          namespace: namespace,
          version: data[:version] || data["version"] || "0.0.0",
          body: body,
          source_path: data[:source_path] || data["source_path"],
          labels: data[:labels] || data["labels"] || [],
          metadata: data[:metadata] || data["metadata"] || {},
          required_vars: data[:required_vars] || data["required_vars"] || []
        )
      end

      def split_path(prompt_path, data)
        if prompt_path && prompt_path.include?("/")
          pieces = prompt_path.split("/")
          [pieces[0...-1].join("/"), pieces.last]
        else
          namespace = data[:namespace] || data["namespace"] || ""
          name = data[:name] || data["name"] || prompt_path || "prompt"
          [namespace, name]
        end
      end
    end
  end
end

