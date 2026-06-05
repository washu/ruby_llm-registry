# frozen_string_literal: true

require "json"
require "time"

module RubyLlm
  module Registry
    module Adapters
      # SQLite-backed prompt repository.
      class SQLite < Base
        def initialize(path:, table_name: "ruby_llm_registry_prompts")
          require_sqlite3!
          @database = SQLite3::Database.new(path)
          @database.results_as_hash = true
          @table_name = table_name
          ensure_schema!
        end

        def get(path, version: nil, label: nil)
          rows = rows_for_path(path)
          raise PromptNotFoundError, "Prompt path not found: #{path}" if rows.empty?

          row = if version
                  rows.find { |record| record["version"] == Version.parse(version).to_s }
                elsif label
                  label = label.to_sym
                  rows.find { |record| labels_for(record).include?(label) } || rows.find { |record| record["version"] == label.to_s }
                else
                  rows.max_by { |record| Version.parse(record["version"]) }
                end

          raise PromptNotFoundError, "Prompt not found: #{path}" unless row

          prompt_from_row(row)
        end

        def available_versions(path)
          rows_for_path(path).map { |row| Version.parse(row["version"]) }.sort
        end

        def store(prompt, overwrite: false)
          existing = rows_for_path(prompt.path).find { |row| row["version"] == prompt.version.to_s }
          if existing && !overwrite
            raise Error, "Prompt #{prompt.path}@#{prompt.version} already exists"
          end

          data = serialize_prompt(prompt)
          if existing
            update_row(data)
          else
            insert_row(data)
          end
          prompt
        end

        private

        attr_reader :database, :table_name

        def require_sqlite3!
          require "sqlite3"
        rescue LoadError => e
          raise LoadError, "sqlite3 gem is required for the SQLite adapter"
        end

        def ensure_schema!
          database.execute <<~SQL
            CREATE TABLE IF NOT EXISTS #{table_name} (
              path TEXT NOT NULL,
              namespace TEXT NOT NULL,
              name TEXT NOT NULL,
              version TEXT NOT NULL,
              body TEXT NOT NULL,
              labels_json TEXT NOT NULL,
              metadata_json TEXT NOT NULL,
              required_vars_json TEXT NOT NULL,
              source_path TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              UNIQUE(path, version)
            )
          SQL
        end

        def rows_for_path(path)
          database.execute("SELECT * FROM #{table_name} WHERE path = ?", [path])
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
            source_path: prompt.source_path,
            created_at: Time.now.utc.iso8601,
            updated_at: Time.now.utc.iso8601
          }
        end

        def insert_row(data)
          database.execute(
            <<~SQL,
              INSERT INTO #{table_name}
                (path, namespace, name, version, body, labels_json, metadata_json, required_vars_json, source_path, created_at, updated_at)
              VALUES
                (:path, :namespace, :name, :version, :body, :labels_json, :metadata_json, :required_vars_json, :source_path, :created_at, :updated_at)
            SQL
            data
          )
        end

        def update_row(data)
          database.execute(
            <<~SQL,
              UPDATE #{table_name}
              SET namespace = :namespace,
                  name = :name,
                  body = :body,
                  labels_json = :labels_json,
                  metadata_json = :metadata_json,
                  required_vars_json = :required_vars_json,
                  source_path = :source_path,
                  updated_at = :updated_at
              WHERE path = :path AND version = :version
            SQL
            data
          )
        end

        def prompt_from_row(row)
          Prompt.new(
            name: row["name"],
            namespace: row["namespace"],
            version: row["version"],
            body: row["body"],
            source_path: row["source_path"],
            labels: JSON.parse(row["labels_json"] || "[]"),
            metadata: JSON.parse(row["metadata_json"] || "{}"),
            required_vars: JSON.parse(row["required_vars_json"] || "[]")
          )
        end

        def labels_for(row)
          JSON.parse(row["labels_json"] || "[]").map(&:to_sym)
        end
      end
    end
  end
end

