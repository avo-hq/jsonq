# frozen_string_literal: true

require_relative "jsonq/version"
require_relative "jsonq/adapters"
require_relative "jsonq/queryable"
require_relative "jsonq/predicate_builder_extension"
require_relative "jsonq/railtie" if defined?(Rails)

module Jsonq
  class Error < StandardError; end
  class UnsupportedColumnType < Error; end
  class UnsupportedAdapter < Error; end

  def self.setup!
    ActiveRecord::PredicateBuilder.prepend(Jsonq::PredicateBuilderExtension)
  end
end
