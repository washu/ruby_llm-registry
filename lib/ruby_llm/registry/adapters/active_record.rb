# frozen_string_literal: true

require "json"

module RubyLLM
  module Registry
    module Adapters
      # ActiveRecord-backed prompt repository.
      class ActiveRecord < Base
        def initialize(model: nil, table_name: "ruby_llm_registry_prompts")
          require_active_record!
          @model = model || build_model(table_name)
          ensure_schema!
        end

        def get(path, version: nil, label: nil)
          scope = model.where(path: path)
          raise PromptNotFoundError, "Prompt path not found: #{path}" if scope.none?

          record = if version
                     scope.find_by(version: Version.parse(version).to_s)
                   elsif label
                     label = label.to_sym
                     scope.to_a.find { |row| labels_for(row).include?(label) } || scope.find_by(version: label.to_s)
                   else
                     scope.to_a.max_by { |row| Version.parse(row.version) }
                   end

          raise PromptNotFoundError, "Prompt not found: #{path}" unless record

          prompt_from_record(record)
        end

        def available_versions(path)
          model.where(path: path).map { |row| Version.parse(row.version) }.sort
        end

        def store(prompt, overwrite: false)
          existing = model.find_by(path: prompt.path, version: prompt.version.to_s)
          raise Error, "Prompt #{prompt.path}@#{prompt.version} already exists" if existing && !overwrite

          attrs = serialize_prompt(prompt)
          existing ? existing.update!(attrs) : model.create!(attrs)
          prompt
        end

        private

        attr_reader :model

        def require_active_record!
          require "active_record"
        rescue LoadError
          raise LoadError, "active_record gem is required for the ActiveRecord adapter"
        end

        def build_model(table_name)
          Class.new(::ActiveRecord::Base) do
            self.table_name = table_name
          end
        end

        def ensure_schema!
          return if model.connection.data_source_exists?(model.table_name)

          model.connection.create_table(model.table_name) do |table|
            table.string :path, null: false
            table.string :namespace, null: false
            table.string :name, null: false
            table.string :version, null: false
            table.text :body, null: false
            table.text :labels_json, null: false, default: "[]"
            table.text :metadata_json, null: false, default: "{}"
            table.text :required_vars_json, null: false, default: "[]"
            table.string :source_path
            table.timestamps null: false
            table.index %i[path version], unique: true
          end
        end

        def serialize_prompt(prompt)
          {
            path: prompt.path,
            namespace: prompt.namespace,
            name: prompt.name,
            version: prompt.version.to_s,
            body: prompt.body,
            labels_json: JSON.generate(prompt.labels),
            metadata_json: JSON.generate(prompt.metadata),
            required_vars_json: JSON.generate(prompt.required_vars),
            source_path: prompt.source_path
          }
        end

        def prompt_from_record(record)
          Prompt.new(
            name: record.name,
            namespace: record.namespace,
            version: record.version,
            body: record.body,
            source_path: record.source_path,
            labels: JSON.parse(record.labels_json || "[]"),
            metadata: JSON.parse(record.metadata_json || "{}"),
            required_vars: JSON.parse(record.required_vars_json || "[]")
          )
        end

        def labels_for(record)
          JSON.parse(record.labels_json || "[]").map(&:to_sym)
        end
      end
    end
  end
end

