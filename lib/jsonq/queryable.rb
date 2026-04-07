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
      def store_accessor(store_attribute, *keys, prefix: nil, suffix: nil)
        super
        _jsonq_register_keys_for_store(store_attribute, keys) if respond_to?(:jsonq_registry)
      end

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

      def _jsonq_register_keys_for_store(store_attribute, keys)
        store_column_str = store_attribute.to_s

        begin
          _jsonq_validate_json_column!(store_column_str)
        rescue Jsonq::UnsupportedColumnType
          raise
        rescue
          return
        end

        new_entries = {}
        keys.each do |key|
          key_str = key.to_s
          next if columns_hash.key?(key_str)

          new_entries[key_str] = {column: store_column_str, path: [key_str], source: :store_accessor}
        end

        self.jsonq_registry = jsonq_registry.merge(new_entries) if new_entries.any?
      end

      def _jsonq_register_store_accessors
        return unless respond_to?(:stored_attributes) && stored_attributes.present?

        stored_attributes.each do |store_column, keys|
          _jsonq_register_keys_for_store(store_column, keys)
        end
      end

      def _jsonq_validate_json_column!(column_name)
        return unless connected? && table_exists?

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

  module QueryableDsl
    def jsonq_queryable
      include Jsonq::Queryable
    end
  end
end
