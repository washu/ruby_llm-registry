# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"

RSpec.describe "RubyLlm::Registry coverage helpers" do
  include SpecSupport::PromptFixtures

  it "covers registry configuration, backend selection, export, import, and diff helpers" do
    Dir.mktmpdir do |dir|
      prompts_root = File.join(dir, "prompts")
      FileUtils.mkdir_p(File.join(prompts_root, "email", "summarizer"))
      File.write(
        File.join(prompts_root, "email", "summarizer", "v1.0.0.md"),
        <<~MD
          ---
          version: 1.0.0
          labels: [production]
          required_vars: [user_name]
          metadata:
            description: Coverage prompt
          ---

          Hello <%= user_name %>
        MD
      )

      Dir.chdir(dir) do
        RubyLlm::Registry.reset!
        RubyLlm::Registry.configure do |config|
          config.root = nil
          config.manifest_path = nil
          config.default_adapter = :filesystem
          config.default_database_adapter = :sqlite
        end

        filesystem_backend = RubyLlm::Registry.backend
        expect(filesystem_backend).to be_a(RubyLlm::Registry::FilesystemBackend)

        sqlite_backend = RubyLlm::Registry.database_backend(path: File.join(dir, "prompts.db"))
        expect(sqlite_backend).to be_a(RubyLlm::Registry::Adapters::SQLite)

        prompt = RubyLlm::Registry.get("email/summarizer")
        expect(RubyLlm::Registry.export(prompt, format: :hash)).to include(:body, :version)
        expect(RubyLlm::Registry.export(prompt, format: :json)).to include('"version": "1.0.0"')
        expect(RubyLlm::Registry.export("email/summarizer", root: prompts_root, format: :markdown)).to include("Hello <%= user_name %>")
        expect(RubyLlm::Registry.export("email/summarizer", backend: filesystem_backend, format: :yaml)).to include("version: 1.0.0")

        imported_backend = Class.new do
          attr_reader :stored

          def get(*)
            raise "not used"
          end

          def store(prompt)
            @stored = prompt
          end
        end.new

        imported = RubyLlm::Registry.import(prompt.export(format: :markdown), backend: imported_backend)
        expect(imported_backend.stored.version.to_s).to eq("1.0.0")
        expect(imported.version.to_s).to eq("1.0.0")

        diff = RubyLlm::Registry.diff(prompt.export(format: :markdown), prompt.export(format: :markdown))
        expect(diff.changed?).to be(false)
        expect(diff.to_s).to eq("No changes")
        expect(diff.to_h[:left]).to be_a(Hash)

        expect { RubyLlm::Registry.backend(:unknown) }.to raise_error(ArgumentError, /Unknown backend type/)
        expect { RubyLlm::Registry.export(prompt, format: :bogus) }.to raise_error(ArgumentError, /Unsupported export format/)
      end
    end
  ensure
    RubyLlm::Registry.reset!
  end

  it "covers importer format inference and path splitting" do
    hash_prompt = RubyLlm::Registry::Importer.new(
      {
        name: "summarizer",
        namespace: "email",
        version: "2.0.0",
        body: "Body",
        labels: ["production"],
        metadata: { description: "Hash prompt" },
        required_vars: ["user_name"]
      },
      format: :hash
    ).to_prompt

    hash_inferred_prompt = RubyLlm::Registry::Importer.new(
      { body: "Inferred body" },
      format: :bogus,
      path: "research"
    ).to_prompt

    json_prompt = RubyLlm::Registry::Importer.new(
      '  {"name":"summarizer","namespace":"email","version":"2.1.0","body":"Body"}',
      format: :bogus
    ).to_prompt

    yaml_prompt = RubyLlm::Registry::Importer.new(
      <<~YAML,
        ---
        name: summarizer
        namespace: email
        version: 2.2.0
        body: YAML body
        ---
      YAML
      format: :bogus
    ).to_prompt

    plain_yaml_prompt = RubyLlm::Registry::Importer.new(
      <<~YAML,
        name: summarizer
        namespace: docs
        version: 2.4.0
        body: Plain YAML body
      YAML
      format: :bogus
    ).to_prompt

    markdown_prompt = RubyLlm::Registry::Importer.new(
      <<~MD,
        ---
        version: 2.3.0
        labels: [staging]
        required_vars: [user_name]
        metadata:
          description: Markdown prompt
        ---

        Markdown body
      MD
      format: :auto,
      path: "email/summarizer"
    ).to_prompt

    path_prompt = RubyLlm::Registry::Importer.new(
      { body: "Path body" },
      format: :hash,
      path: "research"
    ).to_prompt

    expect(hash_prompt.labels).to eq([:production])
    expect(hash_inferred_prompt.path).to eq("research")
    expect(json_prompt.version.to_s).to eq("2.1.0")
    expect(yaml_prompt.body).to eq("")
    expect(plain_yaml_prompt.namespace).to eq("docs")
    expect(plain_yaml_prompt.body).to eq("Plain YAML body")
    expect(markdown_prompt.path).to eq("email/summarizer")
    expect(path_prompt.path).to eq("research")
  end

  it "covers prompt, comparison, semver, context, and front matter helpers" do
    prompt = load_prompt_fixture(version: "1.1.0")
    other = load_prompt_fixture(version: "1.0.0")

    expect(
      prompt.to_message(
        role: :assistant,
        user_name: "Ava",
        email_body: "Body",
        summary_length: "concise"
      )[:role]
    ).to eq(:assistant)
    context_object = Struct.new(:user_name, :email_body, :summary_length, keyword_init: true).new(user_name: "Ava", email_body: "Body", summary_length: "concise")

    expect(
      prompt.render(
        { user_name: "Ava", email_body: "Body", summary_length: "concise" }
      ).strip
    ).to include("User: Ava")
    expect(prompt.render(context_object).strip).to include("User: Ava")
    expect do
      prompt.render(
        context_object,
        extra: true
      )
    end.to raise_error(ArgumentError, /Pass either a context hash or keyword arguments/)
    expect(prompt.export(format: :hash)).to include(:path, :body)
    expect(prompt.diff(prompt.export(format: :markdown))).to be_a(RubyLlm::Registry::Comparison)

    comparison = prompt.diff(other)
    expect(comparison.changed?).to be(true)
    expect(comparison.changed_fields).to include(:version, :labels, :metadata, :required_vars, :body)
    expect(comparison.to_s).to include("version:")
    expect(comparison.to_h[:right]).to be_a(Hash)

    same = RubyLlm::Registry::Comparison.new(prompt, prompt)
    expect(same.to_s).to eq("No changes")

    stable = RubyLlm::Registry::Version.parse("1.2.3")
    prerelease = RubyLlm::Registry::Version.parse("1.2.3-beta.1")
    expect(stable.stable?).to be(true)
    expect(prerelease.stable?).to be(false)
    expect(stable.inspect).to include("RubyLlm::Registry::Version 1.2.3")
    expect(prerelease < stable).to be(true)

    context = RubyLlm::Registry::RenderContext.new(user_name: "Ava")
    expect(context.respond_to?(:user_name)).to be(true)
    expect(context.respond_to?(:missing)).to be(false)
    expect(context.current_date).to be_a(Date)
    expect(context.current_time).to be_a(Time)
    expect { context.user_name("unexpected") }.to raise_error(NoMethodError)

    raw = RubyLlm::Registry::FrontMatter.parse("plain text")
    invalid = RubyLlm::Registry::FrontMatter.parse("---\nversion: [broken\n---\nbody\n")
    valid = RubyLlm::Registry::FrontMatter.parse(
      <<~MD
        ---
        version: 9.9.9
        labels: [production]
        ---

        body
      MD
    )

    expect(raw).to eq([{}, "plain text"])
    expect(invalid).to eq([{}, "---\nversion: [broken\n---\nbody\n"])
    expect(valid.first).to include(version: "9.9.9", labels: ["production"])
  end

  it "covers adapter base behavior and the adapter factory" do
    prompt = load_prompt_fixture(version: "1.1.0")

    expect(RubyLlm::Registry::Adapters::Base.new.available_versions("anything")).to eq([])
    expect { RubyLlm::Registry::Adapters::Base.new.get("anything") }.to raise_error(NotImplementedError)
    expect { RubyLlm::Registry::Adapters::Base.new.store(prompt) }.to raise_error(NotImplementedError)

    adapter = Class.new(RubyLlm::Registry::Adapters::Base) do
      attr_reader :stored_prompt

      def initialize(prompt)
        @prompt = prompt
      end

      def get(*)
        @prompt
      end

      def store(prompt, **)
        @stored_prompt = prompt
      end
    end.new(prompt)

    expect(adapter.export("ignored", format: :hash)).to include(:version, :labels)
    expect(adapter.export("ignored", format: :json)).to include('"version": "1.1.0"')
    expect(adapter.export("ignored", format: :yaml)).to include("version: 1.1.0")
    expect(adapter.export("ignored", format: :markdown)).to include("version: 1.1.0")
    expect(adapter.import(prompt.export(format: :markdown), format: :markdown)).to be_a(RubyLlm::Registry::Prompt)

    Dir.mktmpdir do |dir|
      filesystem = RubyLlm::Registry::Adapters.build(:filesystem, root: dir)
      expect(filesystem).to be_a(RubyLlm::Registry::FilesystemBackend)
    end

    expect { RubyLlm::Registry::Adapters.build(:bogus) }.to raise_error(ArgumentError, /Unknown adapter type/)
  end

  it "covers filesystem backend error handling and overwrite flow" do
    Dir.mktmpdir do |dir|
      prompt_root = File.join(dir, "prompts", "email", "summarizer")
      FileUtils.mkdir_p(prompt_root)
      File.write(File.join(prompt_root, "v1.0.0.md"), "---\nversion: 1.0.0\n---\nFirst\n")
      File.write(File.join(prompt_root, "v1.1.0.md"), "---\nversion: 1.1.0\nlabels: [latest]\n---\nSecond\n")
      File.write(File.join(dir, "prompts", "manifest.yml"), "not: [valid\n")

      backend = RubyLlm::Registry::FilesystemBackend.new(root: File.join(dir, "prompts"))

      expect(backend.available_versions("missing/path")).to eq([])
      expect { backend.get("missing/path") }.to raise_error(RubyLlm::Registry::PromptNotFoundError)
      expect(backend.get("email/summarizer", version: "1.0.0").body.strip).to eq("First")
      expect(backend.available_versions("email/summarizer").map(&:to_s)).to eq(["1.0.0", "1.1.0"])
      expect(backend.get("email/summarizer", label: :latest).version.to_s).to eq("1.1.0")
      expect(backend.get("email/summarizer", label: :"v1.0.0").version.to_s).to eq("1.0.0")

      prompt = RubyLlm::Registry::Prompt.new(
        name: "summarizer",
        namespace: "email",
        version: "1.2.0",
        body: "Fresh body",
        source_path: nil,
        labels: %i[production],
        metadata: { description: "Overwrite prompt" },
        required_vars: []
      )
      backend.store(prompt)
      expect { backend.store(prompt) }.to raise_error(RubyLlm::Registry::Error)
      expect { backend.store(prompt, overwrite: true) }.not_to raise_error
    end
  end
end



