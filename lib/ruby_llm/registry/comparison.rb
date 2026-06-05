# frozen_string_literal: true

module RubyLLM
  module Registry
    # Represents a comparison between two prompt revisions.
    class Comparison
      attr_reader :left, :right, :changes

      def initialize(left, right)
        @left = left
        @right = right
        @changes = build_changes
      end

      def changed?
        changes.any?
      end

      def changed_fields
        changes.keys
      end

      def body_diff
        DiffLines.new(left.body.to_s, right.body.to_s).to_s
      end

      def to_h
        {
          left: snapshot(left),
          right: snapshot(right),
          changes: changes,
          body_diff: body_diff
        }
      end

      def to_s
        return "No changes" unless changed?

        parts = changes.map do |field, change|
          "#{field}: #{change[:from].inspect} -> #{change[:to].inspect}"
        end
        "#{parts.join('; ')}\n#{body_diff}"
      end

      private

      def build_changes
        fields = %i[version labels metadata required_vars body]
        fields.each_with_object({}) do |field, hash|
          left_value = normalize_field(left.public_send(field))
          right_value = normalize_field(right.public_send(field))
          hash[field] = { from: left_value, to: right_value } unless left_value == right_value
        end
      end

      def normalize_field(value)
        case value
        when Version
          value.to_s
        when Array
          value.map { |item| normalize_field(item) }
        when Hash
          value.each_with_object({}) do |(key, item), hash|
            hash[key] = normalize_field(item)
          end
        else
          value
        end
      end

      def snapshot(prompt)
        prompt.respond_to?(:to_h) ? prompt.to_h : prompt
      end
    end

    # Minimal line-oriented diff representation for prompt bodies.
    class DiffLines
      def initialize(left, right)
        @left = left.to_s.split("\n")
        @right = right.to_s.split("\n")
      end

      def to_s
        build.join("\n")
      end

      private

      attr_reader :left, :right

      def build
        output = []
        max = [left.length, right.length].max

        max.times do |index|
          l = left[index]
          r = right[index]

          if l == r
            output << " #{l}" if l
          else
            output << "-#{l}" if l
            output << "+#{r}" if r
          end
        end

        output
      end
    end
  end
end

