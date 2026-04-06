# frozen_string_literal: true

require "active_support/concern"

module Jsonq
  module Queryable
    extend ActiveSupport::Concern

    included do
      class_attribute :jsonq_registry, instance_writer: false, default: {}
      _jsonq_register_store_accessors
    end

    class_methods do
      def json_attribute(column, path, as: nil)
        raise ArgumentError, "jsonq: `as:` option is required for json_attribute" if as.nil?

        column = column.to_s
        _jsonq_validate_json_column!(column)

        path_parts = path.to_s.split(".")
        alias_name = as.to_s

        self.jsonq_registry = jsonq_registry.merge(
          alias_name => {column: column, path: path_parts, source: :json_attribute}
        )
      end

      private

      def _jsonq_register_store_accessors
        return unless respond_to?(:stored_attributes) && stored_attributes.present?

        registry = {}

        stored_attributes.each do |store_column, keys|
          store_column_str = store_column.to_s

          begin
            _jsonq_validate_json_column!(store_column_str)
          rescue Jsonq::UnsupportedColumnType
            raise
          rescue
            next
          end

          keys.each do |key|
            key_str = key.to_s
            next if columns_hash.key?(key_str)

            registry[key_str] = {column: store_column_str, path: [key_str], source: :store_accessor}
          end
        end

        self.jsonq_registry = registry
      end

      def _jsonq_validate_json_column!(column_name)
        unless connected? && table_exists?
          return
        end

        col = columns_hash[column_name]
        return if col.nil?

        sql_type = col.sql_type.downcase
        unless sql_type.include?("json")
          raise Jsonq::UnsupportedColumnType,
            "jsonq: column '#{column_name}' has type '#{col.sql_type}'. " \
            "Only native JSON/JSONB columns are supported."
        end
      end
    end
  end
end
