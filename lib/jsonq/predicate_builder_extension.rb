# frozen_string_literal: true

module Jsonq
  module PredicateBuilderExtension
    protected

    def expand_from_hash(attributes, &block)
      klass = begin
        @table.send(:klass)
      rescue
        nil
      end

      return super unless klass&.respond_to?(:jsonq_registry) && klass.jsonq_registry.present?

      registry = klass.jsonq_registry
      jsonq_predicates = []
      regular_attributes = {}

      attributes.each do |key, value|
        key_str = key.to_s

        if registry.key?(key_str)
          mapping = registry[key_str]
          adapter = Jsonq::Adapters.for_connection(klass.connection)
          arel_table = klass.arel_table
          path_expr = adapter.build_path_expression(arel_table, mapping[:column], mapping[:path])

          predicate = case value
          when Array
            # Wrap with AND IS NOT NULL so NOT(IN(...) AND IS NOT NULL)
            # becomes NOT IN(...) OR IS NULL — includes missing keys
            Arel::Nodes::Grouping.new(
              path_expr.in(value.map(&:to_s)).and(path_expr.not_eq(nil))
            )
          when nil
            path_expr.eq(nil)
          else
            # Wrap with AND IS NOT NULL so NOT(= val AND IS NOT NULL)
            # becomes != val OR IS NULL — includes missing keys
            Arel::Nodes::Grouping.new(
              path_expr.eq(value.to_s).and(path_expr.not_eq(nil))
            )
          end

          jsonq_predicates << predicate
        else
          regular_attributes[key] = value
        end
      end

      result = regular_attributes.empty? ? [] : super(regular_attributes, &block)
      result + jsonq_predicates
    end
  end
end
