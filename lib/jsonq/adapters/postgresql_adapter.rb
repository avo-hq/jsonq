# frozen_string_literal: true

module Jsonq
  module Adapters
    class PostgresqlAdapter < AbstractAdapter
      def build_path_expression(arel_table, column, path)
        node = arel_table[column]

        path.each_with_index do |key, index|
          operator = (index == path.length - 1) ? "->>" : "->"
          node = Arel::Nodes::InfixOperation.new(operator, node, Arel::Nodes.build_quoted(key))
        end

        node
      end
    end
  end
end
