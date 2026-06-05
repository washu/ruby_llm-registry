# frozen_string_literal: true

require "json"

module RubyLlm
  module Registry
    module Adapters
      # MongoDB-backed prompt repository.
      class MongoDB < Base
        def initialize(collection: nil, database: nil, collection_name: "ruby_llm_registry_prompts")
          @collection = collection || resolve_collection(database, collection_name)
        end

        def get(path, version: nil, label: nil)
          docs = collection.find(path: path).to_a
          raise PromptNotFoundError, "Prompt path not found: #{path}" if docs.empty?

          doc = if version
                  docs.find { |record| record["version"] == Version.parse(version).to_s }
                elsif label
                  label = label.to_sym
                  docs.find { |record| labels_for(record).include?(label) } || docs.find { |record| record["version"] == label.to_s }
                else
                  docs.max_by { |record| Version.parse(record["version"]) }
                end

          raise PromptNotFoundError, "Prompt not found: #{path}" unless doc

          prompt_from_document(doc)
        end

        def available_versions(path)
          collection.find(path: path).map { |doc| Version.parse(doc["version"]) }.sort
        end

        def store(prompt, overwrite: false)
          existing = collection.find(path: prompt.path, version: prompt.version.to_s).first
          if existing && !overwrite
            raise Error, "Prompt #{prompt.path}@#{prompt.version} already exists"
          end

          doc = serialize_prompt(prompt)
          existing ? collection.replace_one({ path: prompt.path, version: prompt.version.to_s }, doc) : collection.insert_one(doc)
          prompt
        end

        private

        attr_reader :collection

        def resolve_collection(database, collection_name)
          raise ArgumentError, "Provide a collection or database" unless database

          database[collection_name]
        end

        def serialize_prompt(prompt)
          {
            "path" => prompt.path,
            "namespace" => prompt.namespace,
            "name" => prompt.name,
            "version" => prompt.version.to_s,
            "body" => prompt.body,
            "labels" => prompt.labels.map(&:to_s),
            "metadata" => prompt.metadata,
            "required_vars" => prompt.required_vars.map(&:to_s),
            "source_path" => prompt.source_path
          }
        end

        def prompt_from_document(doc)
          Prompt.new(
            name: doc["name"],
            namespace: doc["namespace"],
            version: doc["version"],
            body: doc["body"],
            source_path: doc["source_path"],
            labels: doc["labels"] || [],
            metadata: doc["metadata"] || {},
            required_vars: doc["required_vars"] || []
          )
        end

        def labels_for(doc)
          Array(doc["labels"]).map(&:to_sym)
        end
      end
    end
  end
end

