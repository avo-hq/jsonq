# frozen_string_literal: true

require_relative "adapters/abstract_adapter"
require_relative "adapters/postgresql_adapter"
require_relative "adapters/mysql_adapter"
require_relative "adapters/sqlite_adapter"

module Jsonq
  module Adapters
    def self.for_connection(connection)
      case connection.adapter_name
      when /postg/i
        PostgresqlAdapter.new
      when /mysql|trilogy/i
        MysqlAdapter.new
      when /sqlite/i
        SqliteAdapter.new
      else
        raise Jsonq::UnsupportedAdapter,
          "jsonq: unsupported database adapter '#{connection.adapter_name}'. " \
          "Supported adapters: PostgreSQL, MySQL, SQLite."
      end
    end
  end
end
