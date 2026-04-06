# frozen_string_literal: true

module Jsonq
  module Adapters
    class MysqlAdapter < AbstractAdapter
      def build_path_expression(arel_table, column, path)
        json_path = "$.#{path.join(".")}"

        extract = Arel::Nodes::NamedFunction.new(
          "JSON_EXTRACT",
          [arel_table[column], Arel::Nodes.build_quoted(json_path)]
        )

        Arel::Nodes::NamedFunction.new("JSON_UNQUOTE", [extract])
      end
    end
  end
end
