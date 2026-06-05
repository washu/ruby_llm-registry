# frozen_string_literal: true

module RubyLLM
  module Registry
    # Context object used while rendering ERB prompts.
    class RenderContext
      def initialize(values = {})
        @values = normalize(values)
      end

      def method_missing(name, *args)
        raise NoMethodError, "undefined method `#{name}` for #{self}" unless args.empty?

        @values[name]
      end

      def respond_to_missing?(name, _include_private = false)
        @values.key?(name)
      end

      def current_date
        Date.today
      end

      def current_time
        Time.now
      end

      alias today current_date

      private

      def normalize(values)
        values.each_with_object({}) do |(key, value), hash|
          hash[key.to_sym] = value
        end
      end
    end
  end
end
