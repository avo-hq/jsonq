# frozen_string_literal: true

module Jsonq
  module Adapters
    class SqliteAdapter < AbstractAdapter
      def build_path_expression(arel_table, column, path)
        json_path = "$.#{path.join(".")}"

        Arel::Nodes::InfixOperation.new(
          "->>",
          arel_table[column],
          Arel::Nodes.build_quoted(json_path)
        )
      end
    end
  end
end
