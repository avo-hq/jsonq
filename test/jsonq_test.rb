# frozen_string_literal: true

require "test_helper"

# Test models
class Plan < ActiveRecord::Base
  store_accessor :metadata, :private_title, :private_description, :category

  jsonq_queryable

  json_attribute :metadata, "nested.deep.value", as: :deep_value
end

class Article < ActiveRecord::Base
  store_accessor :settings, :theme
end

class PlanWithoutJsonq < ActiveRecord::Base
  self.table_name = "plans"
  store_accessor :metadata, :private_title
end

# === Queryable Module Tests ===

class QueryableTest < Minitest::Test
  def test_registers_store_accessor_attributes
    registry = Plan.jsonq_registry

    assert registry.key?("private_title")
    assert registry.key?("private_description")
    assert registry.key?("category")
    assert_equal "metadata", registry["private_title"][:column]
    assert_equal ["private_title"], registry["private_title"][:path]
    assert_equal :store_accessor, registry["private_title"][:source]
  end

  def test_model_without_jsonq_has_no_registry
    refute Article.respond_to?(:jsonq_registry)
  end

  def test_model_with_no_store_accessor
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "plans"
      jsonq_queryable
    end

    assert_equal({}, klass.jsonq_registry)
  end

  def test_column_collision_skips_real_column
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "plans"
      store_accessor :metadata, :custom_field, :status
      jsonq_queryable
    end

    registry = klass.jsonq_registry
    assert registry.key?("custom_field"), "non-column key should be registered"
    refute registry.key?("status"), "status is a real column and should be skipped"
  end

  def test_unsupported_column_type_raises
    assert_raises(Jsonq::UnsupportedColumnType) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        store_accessor :settings, :theme
        jsonq_queryable
      end
    end
  end

  def test_store_accessor_after_jsonq_queryable
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "plans"
      jsonq_queryable
      store_accessor :metadata, :late_field, :another_field
    end

    registry = klass.jsonq_registry
    assert registry.key?("late_field"), "store_accessor declared after jsonq_queryable should be registered"
    assert registry.key?("another_field"), "store_accessor declared after jsonq_queryable should be registered"
    assert_equal "metadata", registry["late_field"][:column]
  end

  def test_store_accessor_before_and_after
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "plans"
      store_accessor :metadata, :early_field
      jsonq_queryable
      store_accessor :metadata, :late_field
    end

    registry = klass.jsonq_registry
    assert registry.key?("early_field"), "store_accessor before jsonq_queryable should be registered"
    assert registry.key?("late_field"), "store_accessor after jsonq_queryable should be registered"
  end

  def test_multiple_store_accessors_on_different_columns
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "plans"
      jsonq_queryable
      store_accessor :metadata, :field_a
    end

    registry = klass.jsonq_registry
    assert registry.key?("field_a")
    assert_equal "metadata", registry["field_a"][:column]
  end
end

# === json_attribute DSL Tests ===

class JsonAttributeTest < Minitest::Test
  def test_registers_simple_path
    registry = Plan.jsonq_registry

    assert registry.key?("deep_value")
    assert_equal "metadata", registry["deep_value"][:column]
    assert_equal ["nested", "deep", "value"], registry["deep_value"][:path]
    assert_equal :json_attribute, registry["deep_value"][:source]
  end

  def test_coexists_with_store_accessor
    registry = Plan.jsonq_registry

    assert registry.key?("private_title"), "store_accessor attribute should be registered"
    assert registry.key?("deep_value"), "json_attribute should be registered"
  end

  def test_missing_as_raises
    assert_raises(ArgumentError) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "plans"
        jsonq_queryable
        json_attribute :metadata, "some.path"
      end
    end
  end
end

# === Adapter Tests ===

class AdaptersTest < Minitest::Test
  def test_sqlite_adapter_detection
    adapter = Jsonq::Adapters.for_connection(ActiveRecord::Base.connection)

    assert_instance_of Jsonq::Adapters::SqliteAdapter, adapter
  end

  def test_unsupported_adapter_raises
    fake_connection = Object.new
    def fake_connection.adapter_name = "OracleEnhanced"

    assert_raises(Jsonq::UnsupportedAdapter) do
      Jsonq::Adapters.for_connection(fake_connection)
    end
  end

  def test_sqlite_single_level_path
    adapter = Jsonq::Adapters::SqliteAdapter.new
    table = Arel::Table.new(:plans)
    expr = adapter.build_path_expression(table, "metadata", ["title"])

    sql = expr.to_sql
    assert_includes sql, "->>"
    assert_includes sql, "metadata"
    assert_includes sql, "title"
  end

  def test_sqlite_nested_path
    adapter = Jsonq::Adapters::SqliteAdapter.new
    table = Arel::Table.new(:plans)
    expr = adapter.build_path_expression(table, "metadata", ["address", "city"])

    sql = expr.to_sql
    assert_includes sql, "->>"
    assert_includes sql, "$.address.city"
  end

  def test_postgresql_single_level_path
    adapter = Jsonq::Adapters::PostgresqlAdapter.new
    table = Arel::Table.new(:plans)
    expr = adapter.build_path_expression(table, "metadata", ["title"])

    sql = expr.to_sql
    assert_includes sql, "->>"
    assert_includes sql, "title"
  end

  def test_postgresql_nested_path
    adapter = Jsonq::Adapters::PostgresqlAdapter.new
    table = Arel::Table.new(:plans)
    expr = adapter.build_path_expression(table, "metadata", ["address", "city"])

    sql = expr.to_sql
    assert_includes sql, "->"
    assert_includes sql, "->>"
    assert_includes sql, "address"
    assert_includes sql, "city"
  end

  def test_mysql_path
    adapter = Jsonq::Adapters::MysqlAdapter.new
    table = Arel::Table.new(:plans)
    expr = adapter.build_path_expression(table, "metadata", ["address", "city"])

    sql = expr.to_sql
    assert_includes sql, "JSON_UNQUOTE"
    assert_includes sql, "JSON_EXTRACT"
    assert_includes sql, "$.address.city"
  end
end

# === Integration Tests (SQLite) ===

class IntegrationTest < Minitest::Test
  def setup
    Plan.delete_all

    plan_a = Plan.new(name: "Plan A", status: "active")
    plan_a.private_title = "Draft"
    plan_a.private_description = "A desc"
    plan_a.category = "work"
    plan_a.save!

    plan_b = Plan.new(name: "Plan B", status: "active")
    plan_b.private_title = "Published"
    plan_b.private_description = "B desc"
    plan_b.category = "personal"
    plan_b.save!

    plan_c = Plan.new(name: "Plan C", status: "archived")
    plan_c.private_title = "Draft"
    plan_c.category = "work"
    plan_c.save!

    Plan.create!(name: "Plan D", status: "active", metadata: "{}")
    Plan.create!(name: "Plan E", status: "active", metadata: nil)
  end

  def test_equality_query
    results = Plan.where(private_title: "Draft")

    assert_equal 2, results.count
    assert_includes results.map(&:name), "Plan A"
    assert_includes results.map(&:name), "Plan C"
  end

  def test_nil_query_matches_missing_and_null
    results = Plan.where(private_title: nil)

    assert_includes results.map(&:name), "Plan D"
    assert_includes results.map(&:name), "Plan E"
  end

  def test_array_in_query
    results = Plan.where(private_title: ["Draft", "Published"])

    assert_equal 3, results.count
  end

  def test_negation_query
    results = Plan.where.not(private_title: "Draft")
    names = results.map(&:name)

    assert_includes names, "Plan B", "non-matching value should be included"
    refute_includes names, "Plan A", "matching value should be excluded"
    refute_includes names, "Plan C", "matching value should be excluded"
    assert_includes names, "Plan D", "missing key (empty JSON) should be included"
    assert_includes names, "Plan E", "nil metadata should be included"
  end

  def test_composition_with_real_column
    results = Plan.where(private_title: "Draft", status: "active")

    assert_equal 1, results.count
    assert_equal "Plan A", results.first.name
  end

  def test_chaining
    results = Plan.where(private_title: "Draft").where(category: "work")

    assert_equal 2, results.count
  end

  def test_non_jsonq_model_unaffected
    results = PlanWithoutJsonq.where(status: "active")

    assert_equal 4, results.count
  end

  def test_store_accessor_getters_still_work
    plan = Plan.find_by(name: "Plan A")

    assert_equal "Draft", plan.private_title
    assert_equal "A desc", plan.private_description
  end
end
