# frozen_string_literal: true

require "aws-sdk-s3"
require "active_record"
require "mongo"
require "logger"
require "tmpdir"

RSpec.describe "RubyLLM::Registry storage backends" do
  include SpecSupport::PromptFixtures

  after do
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
  rescue StandardError
    nil
  end

  describe "filesystem fixtures" do
    it "loads real prompt files from the fixtures tree" do
      prompt = load_prompt_fixture(version: "1.1.0")

      expect(prompt.version.to_s).to eq("1.1.0")
      expect(prompt.labels).to include(:production, :latest)
      expect(prompt.metadata[:owner]).to eq("growth-team")
      expect(prompt.render(user_name: "Ava", email_body: "Thanks for the update", summary_length: "concise").strip).to include("User: Ava")
    end

    it "round-trips a fixture prompt through the importer and exporter" do
      markdown = File.read(prompt_fixture_path("email", "summarizer", "v1.1.0.md"))
      imported = RubyLLM::Registry.import(markdown, format: :markdown)

      expect(imported.version.to_s).to eq("1.1.0")
      expect(imported.export(format: :json)).to include('"version": "1.1.0"')
    end
  end

  describe "SQLite backend" do
    it "persists and reloads prompts from a sqlite database" do
      Dir.mktmpdir do |dir|
        backend = RubyLLM::Registry.database_backend(:sqlite, path: File.join(dir, "prompts.db"))
        prompt = load_prompt_fixture(version: "1.1.0")

        backend.store(prompt)
        reloaded = backend.get("email/summarizer", version: "1.1.0")

        expect(reloaded.render(user_name: "Ava", email_body: "Hello", summary_length: "3").strip).to include("User: Ava")
        expect(backend.available_versions("email/summarizer").map(&:to_s)).to eq(["1.1.0"])
      end
    end
  end

  describe "ActiveRecord backend" do
    it "uses the same prompt model through ActiveRecord" do
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      backend = RubyLLM::Registry.database_backend(:active_record)
      prompt = load_prompt_fixture(version: "1.0.0")

      backend.store(prompt)
      stored = backend.get("email/summarizer", version: "1.0.0")

      expect(stored.version.to_s).to eq("1.0.0")
      expect(stored.labels).to include(:staging)
      expect(backend.available_versions("email/summarizer").map(&:to_s)).to eq(["1.0.0"])
    end
  end

  describe "MongoDB backend" do
    before(:context) do
      @mongo_original_stderr = $stderr
      $stderr = File.open(File::NULL, "w")
      @mongo_previous_logger = Mongo::Logger.logger
      Mongo::Logger.logger = Logger.new(File::NULL)
    end

    before(:context) do
      @mongo_service_unavailable = !SpecSupport::DockerService.available?
      next if @mongo_service_unavailable

      @mongo_service = SpecSupport::DockerService.new(
        image: "mongo:8",
        container_port: 27_017,
        command: [],
        name_prefix: "ruby-llm-registry-mongo",
        ready_check: lambda do |service|
          client = Mongo::Client.new("mongodb://127.0.0.1:#{service.host_port}/admin", server_selection_timeout: 2)
          begin
            client.database.command(ping: 1)
            true
          ensure
            client&.close
          end
        end
      )

      @mongo_service_unavailable = !@mongo_service.boot(timeout_seconds: 30)
    end

    after(:context) do
      Mongo::Logger.logger = @mongo_previous_logger if defined?(@mongo_previous_logger) && @mongo_previous_logger
      $stderr = @mongo_original_stderr if defined?(@mongo_original_stderr) && @mongo_original_stderr
      @mongo_service&.stop
    end

    it "round-trips prompt versions through MongoDB" do
      skip "Docker is unavailable" if @mongo_service_unavailable

      client = Mongo::Client.new("mongodb://127.0.0.1:#{@mongo_service.host_port}/ruby_llm_registry_test", server_selection_timeout: 5)
      begin
        collection = client[:prompts]
        collection.delete_many
        backend = RubyLLM::Registry.backend(:mongo, collection: collection)
        prompt = load_prompt_fixture(version: "1.1.0")

        backend.store(prompt)
        reloaded = backend.get("email/summarizer", version: "1.1.0")

        expect(reloaded.labels).to include(:production, :latest)
        expect(backend.available_versions("email/summarizer").map(&:to_s)).to eq(["1.1.0"])
      ensure
        client&.close
      end
    end
  end

  describe "S3 backend via MinIO" do
    before(:context) do
      @s3_service_unavailable = !SpecSupport::DockerService.available?
      next if @s3_service_unavailable

      @s3_service = SpecSupport::DockerService.new(
        image: "minio/minio:latest",
        container_port: 9000,
        env: {
          "MINIO_ROOT_USER" => "minioadmin",
          "MINIO_ROOT_PASSWORD" => "minioadmin"
        },
        command: ["server", "/data", "--console-address", ":9001"],
        name_prefix: "ruby-llm-registry-minio",
        ready_check: lambda { |service|
          client = Aws::S3::Client.new(
            region: "us-east-1",
            endpoint: "http://127.0.0.1:#{service.host_port}",
            force_path_style: true,
            credentials: Aws::Credentials.new("minioadmin", "minioadmin")
          )
          client.list_buckets
          true
        }
      )

      @s3_service_unavailable = !@s3_service.boot
    end

    after(:context) do
      @s3_service&.stop
    end

    it "stores and loads prompts from S3-compatible storage" do
      skip "Docker is unavailable" if @s3_service_unavailable

      client = Aws::S3::Client.new(
        region: "us-east-1",
        endpoint: "http://127.0.0.1:#{@s3_service.host_port}",
        force_path_style: true,
        credentials: Aws::Credentials.new("minioadmin", "minioadmin")
      )
      bucket = "ruby-llm-registry-test"
      client.create_bucket(bucket: bucket)
      backend = RubyLLM::Registry.backend(:s3, client: client, bucket: bucket)
      prompt = load_prompt_fixture(version: "1.1.0")

      backend.store(prompt)
      reloaded = backend.get("email/summarizer", version: "1.1.0")

      expect(reloaded.version.to_s).to eq("1.1.0")
      expect(reloaded.labels).to include(:production)
      expect(backend.available_versions("email/summarizer").map(&:to_s)).to eq(["1.1.0"])
    end
  end
end

