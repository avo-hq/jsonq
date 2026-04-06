require_relative "lib/jsonq/version"

Gem::Specification.new do |s|
  s.name = "jsonq"
  s.version = Jsonq::VERSION
  s.summary = "Friendly JSON column queries for ActiveRecord."
  s.description = "Query JSON/JSONB columns using ActiveRecord's where syntax. Works with store_accessor and supports PostgreSQL, MySQL, and SQLite."
  s.authors = ["Adrian Marin"]
  s.email = "adrian@adrianthedev.com"
  s.homepage = "https://github.com/avo-hq/jsonq"
  s.license = "MIT"

  s.metadata["homepage_uri"] = s.homepage
  s.metadata["source_code_uri"] = s.homepage
  s.metadata["bug_tracker_uri"] = "#{s.homepage}/issues"
  s.metadata["changelog_uri"] = "#{s.homepage}/releases"

  s.files = Dir["lib/**/*", "LICENSE", "README.md"]

  s.required_ruby_version = Gem::Requirement.new(">= 3.0")

  s.add_dependency "activerecord", ">= 7.0"
end
