# frozen_string_literal: true

module RubyLLM
  module Registry
    class Version
      include Comparable

      VERSION_PATTERN = /\Av?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?\z/

      attr_reader :major, :minor, :patch, :prerelease

      def self.parse(value)
        match = VERSION_PATTERN.match(value.to_s)
        raise InvalidVersionError, "Invalid semantic version: #{value.inspect}" unless match

        new(
          major: match[1].to_i,
          minor: match[2].to_i,
          patch: match[3].to_i,
          prerelease: match[4]
        )
      end

      def initialize(major:, minor:, patch:, prerelease: nil)
        @major = major
        @minor = minor
        @patch = patch
        @prerelease = prerelease
      end

      def <=>(other)
        other = self.class.parse(other) unless other.is_a?(self.class)

        [major, minor, patch, release_rank, prerelease.to_s] <=> [other.major, other.minor, other.patch, other.release_rank, other.prerelease.to_s]
      end

      def release_rank
        prerelease.nil? ? 1 : 0
      end

      def stable?
        prerelease.nil?
      end

      def to_s
        base = "#{major}.#{minor}.#{patch}"
        prerelease.nil? ? base : "#{base}-#{prerelease}"
      end

      def inspect
        "#<#{self.class.name} #{self}>"
      end
    end
  end
end
