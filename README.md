# jsonq

[![Testing](https://github.com/avo-hq/jsonq/actions/workflows/testing.yml/badge.svg)](https://github.com/avo-hq/jsonq/actions/workflows/testing.yml)

Friendly JSON column queries for ActiveRecord. Use `where` with JSON attributes just like regular columns.

Supports PostgreSQL, MySQL, and SQLite.

## Installation

Add to your Gemfile:

```ruby
gem "jsonq"
```

## Getting Started

Add `jsonq_queryable` to your model:

```ruby
class Plan < ApplicationRecord
  jsonq_queryable

  store_accessor :metadata, :private_title, :category, :author
end
```

Order doesn't matter — `jsonq_queryable` can go before or after `store_accessor`.

Now query JSON attributes with `where`:

```ruby
Plan.where(private_title: "Draft")
Plan.where(category: "work", status: "active")
Plan.where(private_title: ["Draft", "Review"])
Plan.where(private_title: nil)
Plan.where.not(category: "archived")
```

## How It Works

jsonq intercepts ActiveRecord's `PredicateBuilder` to translate JSON attribute names into database-specific path expressions:

```
Plan.where(private_title: "Draft")
```

Generates:

```sql
-- PostgreSQL
WHERE "plans"."metadata"->>'private_title' = 'Draft'

-- MySQL
WHERE JSON_UNQUOTE(JSON_EXTRACT("plans"."metadata", '$.private_title')) = 'Draft'

-- SQLite
WHERE "plans"."metadata"->>'$.private_title' = 'Draft'
```

## store_accessor Integration

Any `store_accessor` attributes on a native JSON/JSONB column are automatically registered. Declarations before or after `jsonq_queryable` both work.

```ruby
class Plan < ApplicationRecord
  jsonq_queryable

  store_accessor :metadata, :private_title, :category
end

Plan.where(private_title: "Draft")
```

When a `store_accessor` attribute name collides with a real database column, the real column takes precedence.

Attributes declared with `prefix:` or `suffix:` are registered by their original key name (the JSON key), not the prefixed accessor name. Use `json_attribute` to query by a custom name.

## Standalone DSL

For nested JSON paths or attributes without `store_accessor`, use `json_attribute`:

```ruby
class Event < ApplicationRecord
  jsonq_queryable

  json_attribute :metadata, "address.billing.city", as: :billing_city
  json_attribute :metadata, "organizer.name", as: :organizer_name
end

Event.where(billing_city: "Paris")
Event.where(organizer_name: "Alice")
```

The `as:` option is required.

## Query Support

| Operation   | Example                                  |
| ----------- | ---------------------------------------- |
| Equality    | `where(key: "value")`                    |
| Nil/NULL    | `where(key: nil)`                        |
| IN (array)  | `where(key: ["a", "b"])`                 |
| Negation    | `where.not(key: "value")`                |
| Composition | `where(json_key: "x", real_column: "y")` |
| Chaining    | `where(key: "x").where(other_key: "y")`  |

## Database Support

- **PostgreSQL** — JSONB and JSON columns
- **MySQL 5.7+** — JSON columns
- **SQLite 3.38+** — JSON1 extension

The adapter is detected automatically from the ActiveRecord connection.

## Non-Rails Usage

If you use ActiveRecord without Rails, call `Jsonq.setup!` after establishing a connection:

```ruby
require "jsonq"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
Jsonq.setup!
```

## Requirements

- Ruby >= 3.0
- ActiveRecord >= 7.0

## License

MIT

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/avo-hq/jsonq).
