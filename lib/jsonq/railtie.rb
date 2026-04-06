# frozen_string_literal: true

require "rails/railtie"

module Jsonq
  class Railtie < ::Rails::Railtie
    initializer "jsonq.active_record" do
      ActiveSupport.on_load :active_record do
        require "jsonq/predicate_builder_extension"
        ActiveRecord::PredicateBuilder.prepend(Jsonq::PredicateBuilderExtension)
      end
    end
  end
end
