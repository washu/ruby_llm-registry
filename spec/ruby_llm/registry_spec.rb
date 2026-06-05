# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe RubyLLM::Registry do
  around do |example|
    described_class.reset!
    example.run
  ensure
    described_class.reset!
  end

  it "has a version number" do
    expect(RubyLLM::Registry::VERSION).not_to be nil
  end

  it "exports and imports prompts across formats" do
    prompt = load_prompt_fixture(version: "1.1.0")

    markdown = prompt.export(format: :markdown)
    yaml = prompt.export(format: :yaml)
    json = prompt.export(format: :json)

    round_tripped = described_class.import(markdown, format: :markdown)

    expect(markdown).to include("version: 1.1.0")
    expect(described_class.import(yaml, format: :yaml).name).to eq(prompt.name)
    expect(described_class.import(json, format: :json).labels).to eq(prompt.labels)
    expect(round_tripped.version.to_s).to eq("1.1.0")
    expect(round_tripped.render(user_name: "Ava", email_body: "Thanks", summary_length: "concise").strip).to include("User: Ava")
  end

  it "compares prompt revisions" do
    left = load_prompt_fixture(version: "1.0.0")
    right = load_prompt_fixture(version: "1.1.0")

    comparison = described_class.diff(left, right)

    expect(comparison).to be_changed
    expect(comparison.changed_fields).to include(:version, :labels, :metadata, :required_vars, :body)
    expect(comparison.body_diff).to include("-You are a concise email summarizer.")
    expect(comparison.body_diff).to include("+You are an expert email summarizer.")
  end

  it "stores prompts in the default filesystem backend" do
    Dir.mktmpdir do |dir|
      backend = described_class.backend(:filesystem, root: File.join(dir, "prompts"))
      prompt = load_prompt_fixture(version: "1.0.0")

      backend.store(prompt)

      expect(File.exist?(File.join(dir, "prompts", "email", "summarizer", "v1.0.0.md"))).to be(true)
      expect(backend.get("email/summarizer", version: "1.0.0").body.strip).to include("You are a concise email summarizer.")
    end
  end

  it "smoke tests the sqlite backend" do
    Dir.mktmpdir do |dir|
      backend = described_class.database_backend(:sqlite, path: File.join(dir, "registry.db"))
      prompt = load_prompt_fixture(version: "1.0.0")

      backend.store(prompt)
      expect(backend.get("email/summarizer", version: "1.0.0").version.to_s).to eq("1.0.0")
    end
  end

  it "loads the newest prompt by default" do
    Dir.mktmpdir do |dir|
      prompt_root = File.join(dir, "prompts", "email", "summarizer")
      FileUtils.mkdir_p(prompt_root)

      File.write(
        File.join(prompt_root, "v1.0.0.md"),
        <<~MD
          ---
          version: 1.0.0
          labels: [production]
          required_vars: [user_name]
          metadata:
            description: First version
          ---

          Hello <%= user_name %>
        MD
      )

      File.write(
        File.join(prompt_root, "v1.2.3.md"),
        <<~MD
          ---
          version: 1.2.3
          labels: [latest, production]
          required_vars: [user_name]
          metadata:
            description: Latest version
          ---

          Hi <%= user_name %>
        MD
      )

      prompt = described_class.get("email/summarizer", root: File.join(dir, "prompts"))

      expect(prompt.version.to_s).to eq("1.2.3")
      expect(prompt.metadata[:description]).to eq("Latest version")
      expect(prompt.render(user_name: "Ava").strip).to eq("Hi Ava")
    end
  end

  it "resolves labels from manifest metadata" do
    Dir.mktmpdir do |dir|
      prompt_root = File.join(dir, "prompts", "email", "summarizer")
      FileUtils.mkdir_p(prompt_root)

      File.write(File.join(prompt_root, "v2.0.0.md"), "---\nversion: 2.0.0\n---\nProduction\n")
      File.write(File.join(prompt_root, "v2.1.0.md"), "---\nversion: 2.1.0\n---\nStaging\n")

      File.write(
        File.join(dir, "prompts", "manifest.yml"),
        <<~YAML
          prompts:
            email/summarizer:
              aliases:
                production: 2.0.0
                staging: 2.1.0
        YAML
      )

      production = described_class.get("email/summarizer", label: :production, root: File.join(dir, "prompts"))
      staging = described_class.get("email/summarizer", label: :staging, root: File.join(dir, "prompts"))

      expect(production.version.to_s).to eq("2.0.0")
      expect(staging.version.to_s).to eq("2.1.0")
    end
  end

  it "raises when required variables are missing" do
    Dir.mktmpdir do |dir|
      prompt_root = File.join(dir, "prompts", "email", "summarizer")
      FileUtils.mkdir_p(prompt_root)
      File.write(
        File.join(prompt_root, "v1.0.0.md"),
        <<~MD
          ---
          version: 1.0.0
          required_vars: [user_name]
          ---

          Hello <%= user_name %>
        MD
      )

      prompt = described_class.get("email/summarizer", version: "1.0.0", root: File.join(dir, "prompts"))

      expect { prompt.render }.to raise_error(RubyLLM::Registry::MissingVariableError)
    end
  end
end
