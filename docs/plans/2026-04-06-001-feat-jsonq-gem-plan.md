---
title: "feat: Build jsonq gem — friendly JSON column queries for ActiveRecord"
type: feat
status: completed
date: 2026-04-06
origin: docs/brainstorms/2026-04-06-jsonq-requirements.md
---

# feat: Build jsonq gem — friendly JSON column queries for ActiveRecord

## Overview

Build a standalone Ruby gem that makes ActiveRecord JSON/JSONB column queries feel native. Instead of writing raw SQL fragments (`WHERE metadata->>'title' = ?`), developers write `Model.where(title: "Draft")` and jsonq generates the correct database-specific JSON path query. Two entry points: automatic integration with Rails' `store_accessor` (opt-in per model) and a standalone DSL for nested paths and query-only use cases.

## Problem Frame

Rails developers querying JSON columns must drop to raw SQL with database-specific syntax. `store_accessor` gives clean Ruby getters/setters but zero query support. Existing gems like `jsonb_accessor` are PostgreSQL-only and use separate scopes instead of integrating with `where`. jsonq solves this by intercepting `where` at the Arel level to produce proper JSON path queries across PostgreSQL, MySQL, and SQLite. (see origin: docs/brainstorms/2026-04-06-jsonq-requirements.md)

## Requirements Trace

**store_accessor Integration**
- R1. Models opt in via `include Jsonq::Queryable`. Store accessor attributes become usable in `where` clauses
- R2. Non-breaking — models without the module behave identically to stock Rails
- R18. Only activates for native JSON/JSONB columns. Raises error for serialized text columns
- R19. Real database columns take precedence over store_accessor attributes of the same name

**Standalone DSL**
- R3. `json_attribute` method for declaring queryable JSON paths without `store_accessor`
- R4. Arbitrary-depth dot notation: `json_attribute :metadata, "address.billing.city", as: :billing_city`
- R5. `as:` alias is required

**Query Capabilities**
- R6. Equality: `where(key: "value")`
- R7. Nil/NULL: `where(key: nil)` — matches both missing key and JSON null
- R8. Array (IN): `where(key: ["a", "b"])`
- R9. Negation: `where.not(key: "value")`
- R10. Composition: `where(json_key: "x", real_column: "y")`

**Database Support**
- R11. PostgreSQL (JSONB and JSON columns)
- R12. MySQL (JSON columns, 5.7+)
- R13. SQLite (JSON1 extension, 3.38+)
- R14. Auto-detect adapter from ActiveRecord connection

**Packaging**
- R15. MIT, only dependency: `activerecord` (>= 7.0)
- R16. Gem name: `jsonq`
- R17. Standalone gem following the class_variants pattern: manual requires (no auto-loaded engine), optional Railtie hook, Minitest tests, Standard linting, MIT license

## Scope Boundaries

- No `order`, `select`, `pluck` for JSON attributes (v1 is `where` only)
- No range/comparison operators (>, <, between) in v1
- No type casting or validation of JSON values
- No migration helpers or column type management
- No Avo-specific integration in the gem itself
- Standalone DSL does not create getter/setter methods
- store_accessor attributes with `prefix:`/`suffix:` are registered by their original key name (the JSON key), not the prefixed accessor name. Use the standalone DSL to query by a custom name.

## Context & Research

### Relevant Code and Patterns

- **Gem structure:** Follow `/Users/adrian/work/avocado/gems/class_variants/` — manual requires, conditional Railtie, Minitest, Standard linting
- **Railtie pattern:** `ActiveSupport.on_load(:active_record)` to hook into AR (class_variants uses `:action_view`)
- **Adapter abstraction:** avo-query's `QueryExecutor` detects adapter via `connection.adapter_name` and branches per database — same pattern needed here
- **store_accessor metadata:** `Model.stored_attributes` returns `{ column_name => [key_names] }` — this is the public API for discovering store_accessor declarations

### External References

- **PredicateBuilder internals:** `expand_from_hash` in `activerecord/lib/active_record/relation/predicate_builder.rb` is the interception target. It checks `table.has_column?(key)` — store accessor names fail this check, falling to an error path. Prepending here lets us intercept before that error.
- **Arel JSON nodes:** No built-in JSON Arel nodes exist in Rails. Use `Arel::Nodes::InfixOperation` for PostgreSQL operators (`->>`, `->`) and `Arel::Nodes::NamedFunction` for function-based adapters (MySQL `JSON_EXTRACT`, SQLite `json_extract`).
- **Prior art:** `jsonb_accessor` uses separate scopes (`jsonb_where`) — works but sacrifices composability. `activerecord-typedstore` extends store_accessor for types but explicitly provides no query support. Neither intercepts `where`.

## Key Technical Decisions

- **Prepend on `PredicateBuilder#expand_from_hash`** for where-interception: This is the narrowest, most targeted point. It produces standard Arel nodes, so `.where.not`, `.or`, `.merge`, and chaining all work automatically without extra code. `expand_from_hash` has been stable since Rails 5. Risk: it's a protected method; mitigated by pinning `activerecord >= 7.0, < 9` and testing against edge Rails.

- **Adapter detection at query time, not boot time**: Use `model.connection.adapter_name` when building the Arel node, not when the module is included. This supports multi-database Rails apps where different models connect to different databases (R14).

- **Column type validation at include time**: When `Jsonq::Queryable` is included, inspect `columns_hash` to verify backing columns are native JSON/JSONB. Raise `Jsonq::UnsupportedColumnType` for serialized text columns (R18). This is a class-level check that runs once.

- **Real columns always win**: When building the registry, skip any store_accessor key whose name matches a key in `columns_hash` (R19). The PredicateBuilder's normal path handles real columns; jsonq only intercepts keys that aren't real columns.

- **Nil means both "missing key" and "JSON null"**: All three databases return NULL from path extraction when the key is missing OR when the value is JSON null. `where(key: nil)` generates `json_path_expression IS NULL` across all adapters. This is the natural behavior and matches Ruby hash semantics.

- **Text extraction for all comparisons**: Use `->>` (PostgreSQL), `JSON_UNQUOTE(JSON_EXTRACT(...))` (MySQL), `->>` (SQLite 3.38+) to extract values as text. All three operators return text, enabling consistent string comparison across databases. Document that users should pass string values for consistent results.

- **store_accessor prefix/suffix: query by original key**: `stored_attributes` only stores original key names. `where(title: "Draft")` works (original key). For prefixed accessor name, use the standalone DSL: `json_attribute :metadata, "title", as: :private_title`.

## Open Questions

### Resolved During Planning

- **How to intercept `where`?** Prepend on `PredicateBuilder#expand_from_hash`. Produces Arel nodes that compose naturally. Narrowest interception point with stable API surface since Rails 5.
- **Does Rails have native JSON query support?** No. Confirmed through Rails 8.1.3 — zero structured JSON path querying. Only raw SQL strings.
- **Nil semantics?** Both "missing key" and "JSON null" match `where(key: nil)`. This is the natural behavior across all three databases and matches Ruby hash semantics.
- **Prefix/suffix handling?** Query by original key name from `stored_attributes`. Standalone DSL covers custom naming.
- **Monkeypatch vs prepend?** `Module#prepend` on `PredicateBuilder`. Preserves `super` chains, plays well with other gems.

### Deferred to Implementation

- **Exact Arel node construction per adapter**: The adapter classes will build `InfixOperation` (PostgreSQL) or `NamedFunction` (MySQL/SQLite) nodes. Exact construction depends on how Arel renders these in each adapter's visitor. Validate with integration tests.
- **PostgreSQL JSON vs JSONB operator differences**: Both use `->>` for text extraction, but JSONB supports `@>` containment which could be more efficient for equality. v1 uses `->>` for both; `@>` optimization can be added later.
- **Edge cases with nested arrays in JSON paths**: Dot notation handles object nesting. Array index access (e.g., `items.0.name`) is out of scope for v1.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
User writes:  Plan.where(private_title: "Draft", status: "active")
                    │
                    ▼
        ActiveRecord::Relation#where(hash)
                    │
                    ▼
        PredicateBuilder#expand_from_hash(attributes)
                    │
      ┌─────────────┴─────────────┐
      │ Jsonq prepend intercepts  │
      │ Partition keys into:      │
      │  - jsonq registry keys    │
      │  - regular keys           │
      └─────────────┬─────────────┘
                    │
      ┌─────────┬───┴───────────┐
      ▼                         ▼
  Regular keys              JSON keys
  (pass to super)           (build Arel via adapter)
      │                         │
      │              ┌──────────┼──────────┐
      │              ▼          ▼          ▼
      │          PostgreSQL   MySQL     SQLite
      │          col->>'key'  JSON_     json_
      │                       EXTRACT   extract
      │              │          │          │
      │              └──────────┼──────────┘
      │                         │
      │                    Arel::Node
      │                    (.eq, .in,
      │                     .is_null)
      │                         │
      └─────────┬───────────────┘
                ▼
         Combined predicates
         (standard Arel nodes)
                │
                ▼
         WHERE "plans"."status" = 'active'
         AND "plans"."metadata"->>'private_title' = 'Draft'
```

**Registry structure per model:**

All registry keys are normalized to strings (via `to_s`) on registration. The `expand_from_hash` prepend converts keys to strings before registry lookup to handle both symbol and string keys from `where` calls.

```
Model.jsonq_registry = {
  "private_title" => { column: :metadata, path: ["private_title"], source: :store_accessor },
  "billing_city"  => { column: :metadata, path: ["address", "billing", "city"], source: :json_attribute }
}
```

## Implementation Units

- [ ] **Unit 1: Gem scaffold**

**Goal:** Set up the gem structure following class_variants conventions.

**Requirements:** R15, R16, R17

**Dependencies:** None

**Files:**
- Create: `jsonq.gemspec`
- Create: `Gemfile`
- Create: `Rakefile`
- Create: `LICENSE`
- Create: `lib/jsonq.rb`
- Create: `lib/jsonq/version.rb`
- Create: `lib/jsonq/railtie.rb`
- Create: `.rubocop.yml`
- Create: `.editorconfig`
- Create: `.gitignore`

**Approach:**
- Follow class_variants gemspec pattern: `required_ruby_version >= 3.0`, `add_dependency "activerecord", ">= 7.0"`
- Entry point `lib/jsonq.rb`: manual `require_relative` for all files, `require "jsonq/railtie" if defined?(Rails)`
- Railtie: `ActiveSupport.on_load(:active_record)` to prepend PredicateBuilder extension
- Define `Jsonq::Error`, `Jsonq::UnsupportedColumnType`, `Jsonq::UnsupportedAdapter` error classes
- Non-Rails setup: `Jsonq.setup!` method that manually prepends the PredicateBuilder extension

**Patterns to follow:**
- `/Users/adrian/work/avocado/gems/class_variants/class_variants.gemspec`
- `/Users/adrian/work/avocado/gems/class_variants/lib/class_variants.rb`
- `/Users/adrian/work/avocado/gems/class_variants/lib/class_variants/railtie.rb`

**Test expectation:** none — pure scaffolding, tested indirectly by all subsequent units

**Verification:**
- `require "jsonq"` succeeds without errors
- `Jsonq::VERSION` returns a version string

---

- [ ] **Unit 2: Registry and Queryable module**

**Goal:** Build the per-model attribute registry and the `Jsonq::Queryable` concern that hooks into `store_accessor`.

**Requirements:** R1, R2, R18, R19

**Dependencies:** Unit 1

**Files:**
- Create: `lib/jsonq/registry.rb`
- Create: `lib/jsonq/queryable.rb`
- Test: `test/queryable_test.rb`

**Approach:**
- `Jsonq::Registry`: simple hash-like class storing `{ attribute_name => { column:, path: } }` per model
- `Jsonq::Queryable`: `ActiveSupport::Concern` that on `included`:
  1. Adds `jsonq_registry` class accessor
  2. Reads `stored_attributes` to discover existing store_accessor declarations
  3. For each store column, checks `columns_hash[column_name].sql_type` to verify it's `json` or `jsonb` — raises `UnsupportedColumnType` if not
  4. Registers each key, skipping any that collide with `columns_hash` keys (R19)
- The registry maps original key names from `stored_attributes`, not prefixed accessor names

**Patterns to follow:**
- `Model.stored_attributes` API for discovering store_accessor declarations
- `Model.columns_hash[col].sql_type` for column type checking

**Test scenarios:**
- Happy path: Model with `store_accessor :metadata, :title, :description` + `include Jsonq::Queryable` registers both keys
- Happy path: Registry correctly maps attribute name to column and path
- Edge case: Model with no store_accessor — empty registry, no errors
- Edge case: store_accessor attribute name collides with real column — real column wins, attribute skipped from registry
- Error path: store_accessor backed by a text column (not JSON/JSONB) — raises `Jsonq::UnsupportedColumnType`
- Edge case: Multiple store_accessor calls on different JSON columns — all registered correctly under their respective columns

**Verification:**
- `Model.jsonq_registry` returns the expected mapping after including `Jsonq::Queryable`
- Models without the module have no `jsonq_registry`

---

- [ ] **Unit 3: Standalone DSL (`json_attribute`)**

**Goal:** Provide the `json_attribute` class method for declaring queryable JSON paths with explicit aliases.

**Requirements:** R3, R4, R5

**Dependencies:** Unit 2 (uses the same registry)

**Files:**
- Modify: `lib/jsonq/queryable.rb` (add `json_attribute` class method)
- Test: `test/json_attribute_test.rb`

**Approach:**
- `json_attribute :column, "dot.path", as: :alias_name` — parses dot notation into path array, registers in `jsonq_registry`
- `as:` is required — raise `ArgumentError` if missing
- Validates that the column exists and is JSON/JSONB (same check as store_accessor)
- Does NOT create getter/setter methods — just registers for query support

**Patterns to follow:**
- ActiveRecord class method DSL patterns (similar to `store_accessor` itself)

**Test scenarios:**
- Happy path: `json_attribute :metadata, "title", as: :meta_title` registers correctly
- Happy path: Nested path `json_attribute :metadata, "address.billing.city", as: :billing_city` produces path `["address", "billing", "city"]`
- Error path: Missing `as:` raises `ArgumentError`
- Error path: Column doesn't exist or isn't JSON — raises appropriate error
- Edge case: Same alias name as an existing registry entry — last declaration wins or raises
- Integration: Can coexist with store_accessor registrations on the same model

**Verification:**
- `json_attribute` declarations appear in `jsonq_registry` with correct column and path

---

- [ ] **Unit 4: Database adapters**

**Goal:** Build the adapter abstraction that generates database-specific Arel nodes for JSON path extraction.

**Requirements:** R11, R12, R13, R14

**Dependencies:** Unit 1

**Files:**
- Create: `lib/jsonq/adapters/abstract_adapter.rb`
- Create: `lib/jsonq/adapters/postgresql_adapter.rb`
- Create: `lib/jsonq/adapters/mysql_adapter.rb`
- Create: `lib/jsonq/adapters/sqlite_adapter.rb`
- Create: `lib/jsonq/adapters.rb` (adapter detection)
- Test: `test/adapters_test.rb`

**Approach:**
- `AbstractAdapter` defines the interface: `build_path_expression(arel_table, column, path)` returns an Arel node representing the JSON path extraction
- PostgreSQL: chain `Arel::Nodes::InfixOperation` with `->` for intermediate steps and `->>` for the final step (text extraction)
- MySQL: `Arel::Nodes::NamedFunction` wrapping `JSON_UNQUOTE(JSON_EXTRACT(col, '$.path'))` with `$.dot.path` syntax
- SQLite: `Arel::Nodes::InfixOperation` with `->>` operator (available since SQLite 3.38+, matching the plan's minimum version requirement) for text extraction
- `Jsonq::Adapters.for_connection(connection)`: regex match on `connection.adapter_name` — `/postg/i`, `/mysql|trilogy/i`, `/sqlite/i`
- Adapter detection happens at query time, not boot time (supports multi-db apps)

**Patterns to follow:**
- avo-query's adapter detection via `connection.adapter_name`
- Andrew Kane pattern: abstract base class + database-specific subclasses

**Test scenarios:**
- Happy path: PostgreSQL adapter produces `InfixOperation` with `->>` for single-level path
- Happy path: PostgreSQL adapter chains `->` then `->>` for nested path `["address", "city"]`
- Happy path: MySQL adapter produces `JSON_UNQUOTE(JSON_EXTRACT(col, '$.address.city'))`
- Happy path: SQLite adapter produces `col->>'$.address.city'` using `->>` operator
- Happy path: Adapter detection returns correct adapter for each connection type
- Error path: Unknown adapter raises `Jsonq::UnsupportedAdapter`
- Edge case: Trilogy adapter (MySQL-compatible) detected correctly

**Verification:**
- Each adapter produces valid Arel nodes that can be compiled to SQL via `to_sql`
- Adapter detection works for all three database adapters

---

- [ ] **Unit 5: PredicateBuilder extension**

**Goal:** Intercept `where` hash conditions to translate registered JSON attributes into proper JSON path queries.

**Requirements:** R6, R7, R8, R9, R10

**Dependencies:** Units 2, 3, 4

**Files:**
- Create: `lib/jsonq/predicate_builder_extension.rb`
- Modify: `lib/jsonq/railtie.rb` (prepend the extension)
- Test: `test/predicate_builder_test.rb`

**Approach:**
- Prepend module on `ActiveRecord::PredicateBuilder` that overrides `expand_from_hash`
- For each key in the hash, check if the relation's model has `jsonq_registry` and if the key is registered
- If registered: use the adapter to build the JSON path Arel node, then apply the appropriate predicate (`.eq`, `.in`, `.eq(nil)`) based on the value type
- If not registered: pass through to `super` (original behavior)
- Value handling:
  - String/Numeric/Boolean → `.eq(value)` on the path expression
  - `nil` → `.eq(nil)` (IS NULL) on the path expression
  - Array → `.in(values)` on the path expression
- `.where.not` works automatically because Rails wraps predicates in `Arel::Nodes::Not`

**Patterns to follow:**
- `ActiveRecord::PredicateBuilder#expand_from_hash` in Rails source
- `Arel::Predications` for `.eq`, `.in`, `.not_eq` methods

**Test scenarios:**
- Happy path: `Model.where(json_key: "value")` generates correct SQL with JSON path expression
- Happy path: `Model.where(json_key: nil)` generates `IS NULL` on the JSON path expression
- Happy path: `Model.where(json_key: ["a", "b"])` generates `IN ('a', 'b')` on the JSON path expression
- Happy path: `Model.where.not(json_key: "value")` generates `NOT (json_path = 'value')`
- Integration: `Model.where(json_key: "x", real_column: "y")` — JSON key uses path expression, real column uses normal column reference
- Integration: Chaining — `Model.where(json_key: "x").where(other_json_key: "y")` composes correctly
- Edge case: Key not in registry — passes through to ActiveRecord's normal behavior unchanged
- Edge case: Model without `Jsonq::Queryable` — all keys pass through normally
- Error path: Nested path via standalone DSL — `where(billing_city: "NYC")` generates correct multi-level path extraction

**Verification:**
- Generated SQL is syntactically correct for each adapter
- Queries return expected results against a real database
- Non-jsonq models are completely unaffected

---

- [ ] **Unit 6: Integration tests with real databases**

**Goal:** Validate end-to-end behavior against real PostgreSQL, MySQL, and SQLite databases.

**Requirements:** R6-R14, R18, R19

**Dependencies:** Units 1-5

**Files:**
- Create: `test/test_helper.rb`
- Create: `test/integration/postgresql_test.rb`
- Create: `test/integration/mysql_test.rb`
- Create: `test/integration/sqlite_test.rb`

**Approach:**
- Test helper establishes database connections (SQLite in-memory for simplicity, PostgreSQL and MySQL via environment variables for CI)
- Create temporary tables with JSON/JSONB columns, define test models with `store_accessor` and `json_attribute`
- Each integration test file covers the full query capability matrix against its database
- CI runs all three if database servers are available; SQLite always runs

**Patterns to follow:**
- class_variants test structure: `test/test_helper.rb` with `$LOAD_PATH` setup
- Minitest::Test classes with `def setup` for test fixtures

**Test scenarios:**
- Happy path: Equality query returns matching records
- Happy path: Nil query returns records with missing key and JSON null value
- Happy path: Array (IN) query returns records matching any value
- Happy path: Negation query excludes matching records
- Happy path: Composition with real column conditions
- Happy path: Nested path query via standalone DSL
- Integration: store_accessor attribute colliding with real column — real column wins
- Error path: store_accessor on a text column raises `UnsupportedColumnType`
- Edge case: Empty JSON object — nil query matches, equality doesn't

**Verification:**
- All tests pass against each supported database
- SQLite tests run without requiring external database servers

## System-Wide Impact

- **Interaction graph:** The PredicateBuilder prepend affects ALL models in an ActiveRecord application, but only activates when a model has `jsonq_registry`. Models without `Jsonq::Queryable` are completely unaffected.
- **Error propagation:** `UnsupportedColumnType` raised at include-time (class loading), not at query-time. `UnsupportedAdapter` raised at query-time if the database isn't PostgreSQL/MySQL/SQLite.
- **State lifecycle risks:** None — jsonq is stateless. The registry is built at class-load time and is immutable after that.
- **Unchanged invariants:** Standard `where` behavior for all non-jsonq attributes. store_accessor getters/setters are not modified.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `expand_from_hash` is protected API — could change in future Rails versions | Pin `activerecord >= 7.0, < 9`. Test against `main` branch in CI. The method has been stable since Rails 5. |
| PredicateBuilder prepend could conflict with other gems that also prepend | Use `super` properly. The prepend only activates for registered keys; everything else passes through. |
| Type comparison differences across databases (PostgreSQL `->>` returns text, MySQL/SQLite preserve types) | v1 uses text extraction consistently. Document that users should pass string values. |
| `columns_hash` may not be available at include-time if the database hasn't been created yet | Defer column validation to first query if `columns_hash` raises. Or use `connected?` check. |

## Sources & References

- **Origin document:** [docs/brainstorms/2026-04-06-jsonq-requirements.md](docs/brainstorms/2026-04-06-jsonq-requirements.md)
- Related code: `/Users/adrian/work/avocado/gems/class_variants/` (gem structure reference)
- Rails internals: `activerecord/lib/active_record/relation/predicate_builder.rb` — `expand_from_hash` interception target
- Rails internals: `activerecord/lib/active_record/store.rb` — `stored_attributes` metadata API
- Prior art: `jsonb_accessor` gem (separate scopes approach, PostgreSQL-only)
- Prior art: `activerecord-typedstore` gem (store_accessor types, no query support)
