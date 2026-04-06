# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "active_record"
require "jsonq"
require "minitest/autorun"

# Set up an in-memory SQLite database for testing
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Prepend the PredicateBuilder extension for non-Rails testing
Jsonq.setup!

ActiveRecord::Schema.define do
  create_table :plans, force: true do |t|
    t.string :name
    t.string :status
    t.json :metadata
  end

  create_table :articles, force: true do |t|
    t.string :title
    t.text :settings
  end
end
