# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "timeout"

module SpecSupport
  module PromptFixtures
    FIXTURE_ROOT = File.expand_path("../fixtures/prompts", File.dirname(__FILE__))

    def prompt_fixture_root
      FIXTURE_ROOT
    end

    def prompt_fixture_path(*parts)
      File.join(prompt_fixture_root, *parts)
    end

    def load_prompt_fixture(version: "1.1.0")
      RubyLlm::Registry.get("email/summarizer", version: version, root: prompt_fixture_root)
    end
  end

  class DockerService
    attr_reader :container_id, :host_port

    def self.available?
      system("docker", "info", out: File::NULL, err: File::NULL)
    end

    def initialize(image:, container_port:, command:, name_prefix:, ready_check:, env: {})
      @image = image
      @container_port = container_port
      @command = Array(command)
      @env = env
      @name_prefix = name_prefix
      @ready_check = ready_check
      @container_name = "#{name_prefix}-#{Process.pid}-#{SecureRandom.hex(4)}"
    end

    def boot(timeout_seconds: 90)
      return false unless self.class.available?

      run_container!
      resolve_host_port!
      wait_until_ready!(timeout_seconds)
      self
    end

    def stop
      return if container_id.nil?

      system("docker", "rm", "-f", container_id, out: File::NULL, err: File::NULL)
    ensure
      @container_id = nil
      @host_port = nil
    end

    private

    attr_reader :image, :container_port, :command, :env, :name_prefix, :ready_check, :container_name

    def run_container!
      args = ["docker", "run", "-d", "--rm", "--name", container_name, "-p", "127.0.0.1::#{container_port}"]
      env.each { |key, value| args += ["-e", "#{key}=#{value}"] }
      args << image
      args.concat(command)

      stdout, stderr, status = Open3.capture3(*args)
      raise stderr unless status.success?

      @container_id = stdout.strip
    end

    def resolve_host_port!
      stdout, stderr, status = Open3.capture3("docker", "port", container_id, "#{container_port}/tcp")
      raise stderr unless status.success?

      @host_port = stdout.strip.split(":").last
    end

    def wait_until_ready!(timeout_seconds)
      Timeout.timeout(timeout_seconds) do
        loop do
          break if ready_check.call(self)

          sleep 0.5
        end
      end
    end
  end
end

