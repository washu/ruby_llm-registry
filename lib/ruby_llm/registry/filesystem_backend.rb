# frozen_string_literal: true

require "pathname"
require "yaml"

module RubyLLM
  module Registry
    # Filesystem-backed registry adapter.
    class FilesystemBackend
      SUPPORTED_EXTENSIONS = %w[.md .prompt].freeze

      def initialize(root:, manifest_path: nil)
        @root = Pathname.new(root)
        @manifest_path = manifest_path && Pathname.new(manifest_path)
      end

      def get(path, version: nil, label: nil)
        prompt_dir = root.join(path)
        raise PromptNotFoundError, "Prompt path not found: #{path}" unless prompt_dir.directory?

        manifest = load_manifest
        file_path = resolve_file_path(prompt_dir, path, version: version, label: label, manifest: manifest)
        if file_path.nil?
          raise PromptNotFoundError,
                "Prompt not found: #{path}#{lookup_suffix(version: version, label: label)}"
        end

        parse_prompt(path, file_path)
      end

      def available_versions(path)
        prompt_dir = root.join(path)
        return [] unless prompt_dir.directory?

        prompt_dir.children.select { |entry| entry.file? && versioned_prompt_file?(entry) }.map do |entry|
          Version.parse(version_from_filename(entry.basename.to_s))
        end.sort
      end

      def store(prompt, overwrite: false, extension: ".md")
        prompt_dir = root.join(prompt.path)
        prompt_dir.mkpath
        target = prompt_dir.join("v#{prompt.version}#{extension}")
        raise Error, "Prompt already exists: #{target}" if target.exist? && !overwrite

        target.write(Exporter.new(prompt).to_markdown)
        prompt
      end

      private

      attr_reader :root, :manifest_path

      def load_manifest
        manifest_file = manifest_path || root.join("manifest.yml")
        return {} unless manifest_file.file?

        YAML.safe_load(manifest_file.read, aliases: true) || {}
      rescue Psych::SyntaxError
        {}
      end

      def resolve_file_path(prompt_dir, prompt_key, version:, label:, manifest:)
        return resolve_by_version(prompt_dir, version) if version
        return resolve_by_label(prompt_dir, prompt_key, label, manifest) if label

        resolve_latest(prompt_dir)
      end

      def resolve_by_version(prompt_dir, version)
        normalized = Version.parse(version).to_s
        candidates = candidate_files(prompt_dir).select do |entry|
          version_from_filename(entry.basename.to_s) == normalized
        end
        candidates.first
      end

      def resolve_by_label(prompt_dir, prompt_key, label, manifest)
        label = label.to_sym

        if (mapped_version = manifest_version_for(prompt_key, label, manifest))
          return resolve_by_version(prompt_dir, mapped_version)
        end

        direct = candidate_files(prompt_dir).find do |entry|
          entry.basename.to_s.sub(entry.extname, "") == label.to_s || entry.basename.to_s == label.to_s
        end
        return direct if direct

        label == :latest ? resolve_latest(prompt_dir) : nil
      end

      def manifest_version_for(prompt_key, label, manifest)
        prompt_manifest = manifest.dig("prompts", prompt_key) || manifest.dig(:prompts, prompt_key)
        return nil unless prompt_manifest.is_a?(Hash)

        aliases = prompt_manifest["aliases"] || prompt_manifest[:aliases] || {}
        aliases[label.to_s] || aliases[label]
      end

      def resolve_latest(prompt_dir)
        candidate_files(prompt_dir).max_by do |entry|
          Version.parse(version_from_filename(entry.basename.to_s))
        rescue InvalidVersionError
          Version.parse("0.0.0")
        end
      end

      def candidate_files(prompt_dir)
        prompt_dir.children.select { |entry| entry.file? && versioned_prompt_file?(entry) }
      end

      def versioned_prompt_file?(entry)
        SUPPORTED_EXTENSIONS.include?(entry.extname) && entry.basename.to_s.match?(version_file_pattern(entry.extname))
      end

      def version_from_filename(filename)
        filename.sub(/\.(md|prompt)\z/, "").sub(/\Av/, "")
      end

      def parse_prompt(prompt_key, file_path)
        content = file_path.read
        metadata, body = FrontMatter.parse(content)
        file_version = Version.parse(metadata[:version] || version_from_filename(file_path.basename.to_s))
        labels = symbol_list(metadata[:labels] || metadata["labels"])
        required_vars = symbol_list(metadata[:required_vars] || metadata["required_vars"])
        prompt_metadata = metadata[:metadata] || metadata["metadata"] || {}

        Prompt.new(
          name: prompt_key.split("/").last,
          namespace: prompt_key.split("/")[0...-1].join("/"),
          version: file_version,
          body: body,
          source_path: file_path.to_s,
          labels: labels,
          metadata: prompt_metadata,
          required_vars: required_vars
        )
      end

      def symbol_list(values)
        Array(values).map(&:to_sym)
      end

      def version_file_pattern(extension)
        /\Av?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?#{Regexp.escape(extension)}\z/
      end

      def lookup_suffix(version:, label:)
        if version
          " version #{version}"
        elsif label
          " label #{label}"
        else
          ""
        end
      end
    end
  end
end
