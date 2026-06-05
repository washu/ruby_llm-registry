# frozen_string_literal: true

module RubyLlm
  module Registry
    class Error < StandardError; end
    class PromptNotFoundError < Error; end
    class InvalidVersionError < Error; end
    class MissingVariableError < Error; end
    class UnknownLabelError < Error; end
  end
end
