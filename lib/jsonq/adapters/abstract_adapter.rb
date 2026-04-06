# frozen_string_literal: true

module Jsonq
  module Adapters
    class AbstractAdapter
      def build_path_expression(arel_table, column, path)
        raise NotImplementedError, "#{self.class}#build_path_expression must be implemented"
      end
    end
  end
end
