# frozen_string_literal: true

require "json"

module RubyLlm
  module Registry
    module Adapters
      # S3-backed prompt repository.
      class S3 < Base
        def initialize(client:, bucket:, prefix: "prompts")
          @client = client
          @bucket = bucket
          @prefix = prefix.to_s.sub(%r{\A/+|/+$}, "")
        end

        def get(path, version: nil, label: nil)
          key = object_key(path, version: version, label: label)
          raise PromptNotFoundError, "Prompt not found: #{path}" unless key

          payload = client.get_object(bucket: bucket, key: key).body.read
          Importer.new(payload, format: :json, path: path).to_prompt
        rescue NoMethodError
          raise PromptNotFoundError, "Prompt not found: #{path}"
        end

        def available_versions(path)
          prefix_key = object_prefix(path)
          response = client.list_objects_v2(bucket: bucket, prefix: prefix_key)
          Array(response.contents).map do |object|
            version_from_key(object.key)
          end.compact.map { |value| Version.parse(value) }.sort
        end

        def store(prompt, overwrite: false)
          key = object_key(prompt.path, version: prompt.version.to_s)
          if !overwrite && object_exists?(key)
            raise Error, "Prompt #{prompt.path}@#{prompt.version} already exists"
          end

          client.put_object(
            bucket: bucket,
            key: key,
            body: Exporter.new(prompt).to_json,
            content_type: "application/json"
          )
          prompt
        end

        private

        attr_reader :client, :bucket, :prefix

        def object_key(path, version: nil, label: nil)
          if version
            "#{object_prefix(path)}/v#{Version.parse(version)}.json"
          elsif label
            label = label.to_sym
            manifest_key = "#{object_prefix(path)}/#{label}.json"
            object_exists?(manifest_key) ? manifest_key : nil
          else
            latest_key(path)
          end
        end

        def latest_key(path)
          keys = list_keys(path)
          versioned = keys.map { |key| [version_from_key(key), key] }.compact
          versioned.max_by { |version, _key| Version.parse(version) }&.last
        end

        def list_keys(path)
          response = client.list_objects_v2(bucket: bucket, prefix: object_prefix(path))
          Array(response.contents).map(&:key)
        end

        def object_exists?(key)
          client.head_object(bucket: bucket, key: key)
          true
        rescue StandardError
          false
        end

        def object_prefix(path)
          [prefix, path].reject(&:empty?).join("/")
        end

        def version_from_key(key)
          basename = key.split("/").last
          basename.sub(/\.(json|yaml|yml)\z/, "").sub(/\Av/, "")
        end
      end
    end
  end
end

