# frozen_string_literal: true

require_relative "adapters/base"
require_relative "adapters/sqlite"
require_relative "adapters/active_record"
require_relative "adapters/mongo"
require_relative "adapters/s3"

module RubyLLM
  module Registry
    module Adapters
      module_function

      def build(type = :filesystem, **options)
        case type.to_sym
        when :filesystem then FilesystemBackend.new(**options)
        when :sqlite then SQLite.new(**options)
        when :active_record, :ar then ActiveRecord.new(**options)
        when :mongo, :mongodb then MongoDB.new(**options)
        when :s3 then S3.new(**options)
        else
          raise ArgumentError, "Unknown adapter type: #{type.inspect}"
        end
      end
    end
  end
end

