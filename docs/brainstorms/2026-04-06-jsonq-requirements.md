---
date: 2026-04-06
topic: jsonq
---

# jsonq — Friendly JSON Column Queries for ActiveRecord

## Problem Frame

Rails developers querying JSON/JSONB columns must write raw SQL fragments with database-specific syntax (`->`, `->>`, `@>`, `JSON_EXTRACT`, etc.). This breaks the ActiveRecord convention of expressing queries as Ruby hashes. Meanwhile, `store_accessor` gives you clean Ruby getters/setters for JSON keys but provides zero query support — you can write `plan.private_title` but not `Plan.where(private_title: "Draft")`.

jsonq bridges this gap: if ActiveRecord knows about your JSON attributes, you should be able to query them the same way you query regular columns.

**Prior art:** Gems like `jsonb_accessor` and `store_model` exist in this space. `jsonb_accessor` provides queryable JSON attributes but is PostgreSQL-only and doesn't integrate with `store_accessor`. `store_model` focuses on type casting and validation, not querying. jsonq differentiates by: (1) hooking into Rails' existing `store_accessor`, (2) supporting PostgreSQL, MySQL, and SQLite, and (3) being a pure query layer with no opinion on schema or types.

## Requirements

**store_accessor Integration**

- R1. Models opt in to queryable store_accessor attributes by including a module (e.g., `include Jsonq::Queryable`). Once included, all `store_accessor` attributes on that model become usable in `where` clauses — e.g., `Plan.where(private_title: "Draft")` generates the correct JSON path query for the underlying database adapter
- R2. The integration must be non-breaking — models that don't include the module behave identically to stock Rails
- R18. jsonq only activates query support for store_accessor attributes backed by native JSON/JSONB columns. For serialized text columns, it raises a clear error at query time explaining the column type is not supported
- R19. When a store_accessor attribute name collides with a real database column, the real column takes precedence. The JSON attribute is only queryable via the standalone DSL with an explicit alias

**Standalone DSL**

- R3. Provide a standalone method (e.g., `json_attribute`) for declaring queryable JSON paths without using `store_accessor` — useful when you need queries but not getters/setters, or for nested paths
- R4. The standalone DSL supports arbitrary-depth dot notation with an explicit alias: `json_attribute :metadata, "address.billing.city", as: :billing_city`
- R5. The `as:` alias is required — the developer chooses the query name explicitly

**Query Capabilities**

- R6. Support equality: `Plan.where(private_title: "Draft")`
- R7. Support nil/NULL checks: `Plan.where(private_title: nil)` finds records where the key is missing or null
- R8. Support array (IN): `Plan.where(private_title: ["Draft", "Review"])`
- R9. Support negation: `Plan.where.not(private_title: "Draft")`
- R10. Queries must compose naturally with other ActiveRecord conditions: `Plan.where(private_title: "Draft", status: "active")`

**Database Support**

- R11. Support PostgreSQL (JSONB and JSON columns)
- R12. Support MySQL (JSON columns, 5.7+)
- R13. Support SQLite (JSON1 extension, 3.38+)
- R14. The developer does not choose an adapter — jsonq detects the database adapter from the ActiveRecord connection automatically

**Packaging**

- R15. Standalone MIT-licensed gem with no dependencies beyond `activerecord` (>= 7.0)
- R16. Gem name: `jsonq`
- R17. Follow the pattern of other standalone Avo ecosystem gems (class_variants, prop_initializer) — independent, useful to any Rails developer

## Success Criteria

- A developer with an existing `store_accessor` model can add `jsonq` to their Gemfile, include the module, and immediately use `where` with those attributes
- JSON attribute queries compose with standard ActiveRecord chainable scopes
- The same model code works across PostgreSQL, MySQL, and SQLite without conditional logic

## Scope Boundaries

- No `order`, `select`, or `pluck` support for JSON attributes (v1 is `where` only)
- No range/comparison operators (>, <, between) for JSON attributes in v1
- No type casting or validation of JSON values — jsonq is a query layer, not a schema/typing layer (that's store_model's territory)
- No migration helpers or column type management
- No Avo-specific integration in the gem itself (Avo can integrate with it separately)
- The standalone DSL does not create getter/setter methods — use `store_accessor` for that

## Key Decisions

- **Opt-in per model rather than auto-magic**: Models must `include Jsonq::Queryable` to enable store_accessor querying. This avoids silent behavior changes app-wide and makes name collision resolution the developer's explicit choice.
- **Real columns take precedence**: When a store_accessor attribute name collides with a real database column, the real column wins. The JSON path is still queryable via the standalone DSL with an explicit alias.
- **Extend store_accessor rather than replace it**: Augment Rails' built-in mechanism so existing code gains query powers with minimal changes. The standalone DSL covers the gap for nested paths and query-only use cases.
- **Explicit alias required for standalone DSL**: `as:` is mandatory. This avoids magic method-name generation from dot paths and keeps the API predictable.
- **All three major databases at launch**: PostgreSQL, MySQL, and SQLite. Broader reach justifies the adapter abstraction cost since JSON support is mature in all three.
- **where-only scope**: Keeps v1 focused on the highest-value pain point. `order`/`select`/`pluck` and range operators can follow in a future version.

## Dependencies / Assumptions

- Assumes `activerecord` >= 7.0 (reasonable floor for a 2026 gem)
- SQLite support assumes the JSON1 extension is loaded (it is by default in most distributions since 3.38)

## Outstanding Questions

### Deferred to Planning

- [Affects R1][Needs research] How does the gem intercept `where` calls — Arel node injection, `columns_hash` override, or a custom `where` extension? Each approach has different compatibility and upgrade risk across Rails versions.
- [Affects R1][Needs research] Audit Rails 8.0+ for any native JSON query support that already exists — verify the exact gap jsonq fills on each adapter.
- [Affects R11-R13][Technical] Exact SQL generation for each adapter's JSON path syntax (e.g., PostgreSQL `->>/jsonb_path_query` vs MySQL `JSON_EXTRACT` vs SQLite `json_extract`). Note: PostgreSQL JSON and JSONB columns use different operators.
- [Affects R7][Technical] Semantics of nil — should `where(key: nil)` match "key exists but is JSON null" vs "key does not exist"? Both? This may need a follow-up user decision during planning. The R9 negation (`where.not(key: nil)`) depends on this decision.
- [Affects R1][Needs research] Whether to monkeypatch `store_accessor` or use `ActiveSupport::Concern` / `prepend` to hook in cleanly.
- [Affects R1][Technical] How to handle `store_accessor` with `prefix:` and `suffix:` options — which name (raw key or prefixed accessor) is used in `where` clauses?
- [Affects R6-R9][Technical] How boolean and numeric JSON values behave across adapters — PostgreSQL `->>` returns strings, MySQL/SQLite `JSON_EXTRACT` preserves types.

## Next Steps

→ `/ce:plan` for structured implementation planning
