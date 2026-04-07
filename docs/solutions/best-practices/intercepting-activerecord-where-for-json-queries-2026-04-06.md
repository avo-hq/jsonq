---
title: "Intercepting ActiveRecord where for Virtual JSON Attribute Queries"
date: 2026-04-06
category: best-practices
module: jsonq
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - Building a gem or concern that makes virtual attributes queryable via standard where hash syntax
  - Needing database-agnostic JSON column querying across PostgreSQL, MySQL, and SQLite
  - Wanting transparent composition with where.not, .or, .merge, and scopes
tags:
  - activerecord
  - json
  - jsonb
  - arel
  - predicate-builder
  - store-accessor
  - ruby-gem
  - database-adapter
---

# Intercepting ActiveRecord where for Virtual JSON Attribute Queries

## Context

Rails' `store_accessor` gives models virtual attributes backed by JSON columns, but these attributes are invisible to `where`. Calling `.where(title: "x")` on a store_accessor attribute fails because ActiveRecord doesn't know `title` lives inside a JSON column.

The naive workaround is raw SQL: `.where("data->>'title' = ?", "x")`. This leaks database internals, breaks portability across PostgreSQL/MySQL/SQLite, and forces every query author to know the backing column.

The challenge: intercept ActiveRecord's query pipeline at the right point to transparently translate virtual attribute names into correct, database-specific JSON path expressions — without breaking `.where.not`, `.or`, `.merge`, chaining, or scopes.

## Guidance

### The interception point: `PredicateBuilder#expand_from_hash`

Do not intercept at `where` (too early), `to_sql` (too late), or at the relation level (fragile). The single correct point is `ActiveRecord::PredicateBuilder#expand_from_hash` — the method that converts a hash like `{ title: "x" }` into Arel predicate nodes.

This method is:
- **Protected** (not private) — stable since Rails 5
- Called for every hash-style `where`, including `.where.not`, `.or`, and merged relations
- Narrow enough that returning standard Arel nodes means all composition works automatically

Prepend a module that partitions attributes into JSON-registered keys and regular keys:

```ruby
module Jsonq
  module PredicateBuilderExtension
    protected

    def expand_from_hash(attributes, &block)
      klass = @table.send(:klass) rescue nil
      return super unless klass&.respond_to?(:jsonq_registry) && klass.jsonq_registry.present?

      registry = klass.jsonq_registry
      jsonq_predicates = []
      regular_attributes = {}

      attributes.each do |key, value|
        key_str = key.to_s
        if registry.key?(key_str)
          mapping = registry[key_str]
          adapter = Jsonq::Adapters.for_connection(klass.connection)
          path_expr = adapter.build_path_expression(klass.arel_table, mapping[:column], mapping[:path])
          predicate = case value
            when Array then path_expr.in(value.map(&:to_s))
            when nil   then path_expr.eq(nil)
            else            path_expr.eq(value.to_s)
          end
          jsonq_predicates << predicate
        else
          regular_attributes[key] = value
        end
      end

      result = regular_attributes.empty? ? [] : super(regular_attributes, &block)
      result + jsonq_predicates
    end
  end
end
```

Access the model class via `@table.send(:klass)` — `TableMetadata#klass` is private but stable across Rails 5–8.

### Building database-specific Arel nodes

**PostgreSQL** — chain `->` for intermediate keys, `->>` for final key (text extraction):

```ruby
def build_path_expression(arel_table, column, path)
  node = arel_table[column]
  path.each_with_index do |key, index|
    operator = (index == path.length - 1) ? "->>" : "->"
    node = Arel::Nodes::InfixOperation.new(operator, node, Arel::Nodes.build_quoted(key))
  end
  node
end
```

**MySQL** — `JSON_UNQUOTE(JSON_EXTRACT(col, '$.path'))`:

```ruby
def build_path_expression(arel_table, column, path)
  json_path = "$.#{path.join('.')}"
  extract = Arel::Nodes::NamedFunction.new("JSON_EXTRACT", [arel_table[column], Arel::Nodes.build_quoted(json_path)])
  Arel::Nodes::NamedFunction.new("JSON_UNQUOTE", [extract])
end
```

**SQLite 3.38+** — `->>` with `$.path` syntax:

```ruby
def build_path_expression(arel_table, column, path)
  json_path = "$.#{path.join('.')}"
  Arel::Nodes::InfixOperation.new("->>", arel_table[column], Arel::Nodes.build_quoted(json_path))
end
```

### Registry with string normalization

Normalize all registry keys to strings at registration time. Convert incoming keys in `expand_from_hash` via `key.to_s` before lookup. This handles both `where(title: "x")` (symbol) and `where("title" => "x")` (string).

### Adapter detection at query time

Use `connection.adapter_name` at query time, not boot time. Regex match: `/postg/i`, `/mysql|trilogy/i`, `/sqlite/i`. This supports multi-database Rails apps.

### Hooking into store_accessor

Use `Model.stored_attributes` (public Rails API) which returns `{ column_name => [key_names] }`. Skip keys that collide with real database columns via `columns_hash.key?(key_str)`. Check `connected? && table_exists?` before calling `columns_hash` — fail gracefully if database isn't ready.

## Why This Matters

**Correctness at the right abstraction level.** Producing standard Arel nodes at `expand_from_hash` means every upstream composition (`.or`, `.not`, `.merge`, scopes) works without special handling — Rails composes Arel nodes, not `where` hashes.

**No leaking of database details.** Call sites write `Model.where(title: "x")`. The gem owns knowledge of which column, path, and SQL dialect to use.

**Zero impact on opt-out models.** The prepend is global but the early `return super` makes it a no-op for models without a registry.

## When to Apply

- Building a gem that makes virtual attributes queryable via standard `where`
- Needing cross-database JSON querying (PostgreSQL, MySQL, SQLite)
- Wanting automatic composition with `.where.not`, `.or`, `.merge`, and scopes
- Per-model opt-in is acceptable (models must `include` a concern)

Do **not** apply when:
- Raw SQL fragments suffice for your use case
- You need type-aware comparison (casting required)
- Rails version is below 5

## Examples

**Before:**

```ruby
Plan.where("metadata->>'private_title' = ?", "Draft")
Plan.where("metadata->>'author' = ? AND metadata->>'status' = ?", "Alice", "published")
scope :published, -> { where("metadata->>'status' = 'published'") }
```

**After:**

```ruby
class Plan < ApplicationRecord
  include Jsonq::Queryable
  store_accessor :metadata, :private_title, :author, :status
  json_attribute :metadata, "address.billing.city", as: :billing_city
end

Plan.where(private_title: "Draft")
Plan.where(author: "Alice", status: "published")
Plan.where.not(status: "draft")
Plan.where(status: %w[published archived])
Plan.where(billing_city: "Paris")

scope :published, -> { where(status: "published") }
Plan.published.where.not(private_title: nil)
```

## Related

- [jsonq requirements](../../brainstorms/2026-04-06-jsonq-requirements.md) — full requirements and key decisions
- [jsonq implementation plan](../../plans/2026-04-06-001-feat-jsonq-gem-plan.md) — technical plan with research findings
- Prior art: `jsonb_accessor` gem (separate scopes, PostgreSQL-only), `activerecord-typedstore` (types, no queries)
- Rails source: `activerecord/lib/active_record/relation/predicate_builder.rb` — the interception target
- Rails source: `activerecord/lib/active_record/store.rb` — `stored_attributes` metadata API
