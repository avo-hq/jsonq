# frozen_string_literal: true

require "rails/railtie"

module Jsonq
  class Railtie < ::Rails::Railtie
    initializer "jsonq.active_record" do
      ActiveSupport.on_load :active_record do
        ActiveRecord::PredicateBuilder.prepend(Jsonq::PredicateBuilderExtension)
        ActiveRecord::Base.extend(Jsonq::QueryableDsl)
      end
    end
  end
end
