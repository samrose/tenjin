# Advanced Features

This guide explores the advanced capabilities that Tenjin's Elixir-based schema generation enables, which would be much harder to achieve with raw SQL/PostgreSQL.

## 🚀 Advanced Capabilities

### Dynamic Schema Generation

Generate tables and schema elements dynamically at compile time:

```elixir
# Generate tenant-specific tables dynamically
defmodule MultiTenantSchema do
  use Tenjin.Schema
  
  # Generate tables for each tenant at compile time
  for tenant <- Application.get_env(:app, :tenants) do
    table "#{tenant}_users" do
      field :id, :uuid, primary_key: true
      field :email, :text, unique: true
      
      # Tenant-specific fields based on configuration
      for field <- tenant_config(tenant).custom_fields do
        field field.name, field.type, field.options
      end
    end
  end
end
```

### Conditional Schema Elements

Control schema features based on environment or feature flags:

```elixir
# Environment-specific features
table "users" do
  field :id, :uuid, primary_key: true
  field :email, :text, unique: true
  
  # Only add audit fields in production
  if Mix.env() == :prod do
    field :audit_log, :jsonb
    field :compliance_data, :text
    
    policy :select, "Audit compliance" do
      "auth.role() = 'auditor' OR auth.uid() = id"
    end
  end
  
  # Feature flags control schema
  if feature_enabled?(:advanced_analytics) do
    field :analytics_data, :jsonb
    index [:analytics_data], using: :gin
  end
  
  # Development-only helper fields
  if Mix.env() == :dev do
    field :debug_info, :jsonb
  end
end
```

### Schema Composition and Mixins

Create reusable schema components:

```elixir
defmodule Common.Timestamps do
  defmacro add_timestamps do
    quote do
      field :created_at, :timestamptz, default: "now()"
      field :updated_at, :timestamptz, default: "now()"
      field :deleted_at, :timestamptz
    end
  end
end

defmodule Common.Ownership do
  defmacro add_ownership(owner_field \\ :owner_id) do
    quote do
      field unquote(owner_field), :uuid, references: "users(id)"
      
      policy :select, "Owners can view their records" do
        "auth.uid() = #{unquote(owner_field)}"
      end
      
      policy :update, "Owners can update their records" do
        "auth.uid() = #{unquote(owner_field)}"
      end
      
      policy :delete, "Owners can delete their records" do
        "auth.uid() = #{unquote(owner_field)}"
      end
      
      index [unquote(owner_field)]
    end
  end
end

defmodule MySchema do
  use Tenjin.Schema
  import Common.{Timestamps, Ownership}
  
  table "posts" do
    field :id, :uuid, primary_key: true
    field :title, :text, null: false
    field :content, :text
    
    add_timestamps()    # Reusable timestamp fields
    add_ownership()     # Reusable ownership pattern
  end
  
  table "documents" do
    field :id, :uuid, primary_key: true
    field :name, :text, null: false
    field :content, :text
    
    add_timestamps()
    add_ownership(:creator_id)  # Custom owner field name
  end
end
```

### Intelligent Policy Generation

Generate complex RLS policies programmatically:

```elixir
defmodule PolicyGenerator do
  def tenant_isolation_policy(tenant_field \\ :tenant_id) do
    quote do
      policy :all, "Tenant isolation" do
        "#{unquote(tenant_field)} = (auth.jwt() ->> 'tenant_id')::uuid"
      end
    end
  end
  
  def hierarchical_access_policy(hierarchy_field, level_field) do
    quote do
      policy :select, "Hierarchical access control" do
        """
        #{unquote(hierarchy_field)} = any(
          WITH RECURSIVE user_hierarchy AS (
            SELECT id, parent_id, 1 as level
            FROM organizational_units 
            WHERE id = (auth.jwt() ->> 'org_unit_id')::uuid
            
            UNION ALL
            
            SELECT ou.id, ou.parent_id, uh.level + 1
            FROM organizational_units ou
            JOIN user_hierarchy uh ON ou.parent_id = uh.id
            WHERE uh.level < (auth.jwt() ->> 'access_level')::int
          )
          SELECT array_agg(id) FROM user_hierarchy
        )
        """
      end
    end
  end
end

defmodule EnterpriseSchema do
  use Tenjin.Schema
  import PolicyGenerator
  
  table "documents" do
    field :id, :uuid, primary_key: true
    field :tenant_id, :uuid, null: false
    field :org_unit_id, :uuid
    field :classification_level, :integer
    
    enable_rls()
    
    # Apply tenant isolation
    tenant_isolation_policy(:tenant_id)
    
    # Apply hierarchical access control  
    hierarchical_access_policy(:org_unit_id, :classification_level)
  end
end
```

### Cross-Reference Validation

Validate schema integrity at compile time:

```elixir
defmodule SchemaValidator do
  def validate_references(schema) do
    tables = schema.tables
    table_names = MapSet.new(tables, & &1.name)
    
    for table <- tables, field <- table.fields do
      if field.references do
        referenced_table = extract_table_name(field.references)
        unless MapSet.member?(table_names, referenced_table) do
          raise CompileError,
            file: __ENV__.file,
            line: __ENV__.line,
            description: "Invalid reference: table '#{referenced_table}' not found in schema"
        end
      end
    end
    :ok
  end
  
  def validate_policy_conditions(schema) do
    for table <- schema.tables, policy <- table.policies do
      case validate_sql_condition(policy.condition) do
        {:error, reason} ->
          raise CompileError,
            file: __ENV__.file,
            line: __ENV__.line,
            description: "Invalid policy condition in #{table.name}: #{reason}"
        :ok -> :ok
      end
    end
  end
  
  defp extract_table_name(reference) do
    [table | _] = String.split(reference, "(")
    table
  end
  
  defp validate_sql_condition(condition) do
    # Simple validation - in practice, you might use a SQL parser
    cond do
      String.contains?(condition, ["DROP", "DELETE", "UPDATE"]) ->
        {:error, "Potentially dangerous SQL in policy condition"}
      String.length(condition) > 500 ->
        {:error, "Policy condition too complex"}
      true ->
        :ok
    end
  end
end

# Use in your schema module
defmodule MyApp.Schema do
  use Tenjin.Schema
  
  # ... table definitions ...
  
  # Validate at compile time
  @after_compile SchemaValidator
  
  def __after_compile__(env, _bytecode) do
    schema = __schema__()
    SchemaValidator.validate_references(schema)
    SchemaValidator.validate_policy_conditions(schema)
  end
end
```

### Automatic Index Optimization

Generate optimal indexes based on usage patterns:

```elixir
defmodule IndexOptimizer do
  def auto_generate_indexes(table) do
    # Automatically create indexes for foreign keys
    fk_indexes = for field <- table.fields, field.references do
      quote do
        index [unquote(field.name)]
      end
    end
    
    # Create indexes for RLS policy conditions
    policy_indexes = for policy <- table.policies do
      analyze_policy_and_create_indexes(policy)
    end
    
    # Create composite indexes for common patterns
    composite_indexes = generate_composite_indexes(table)
    
    fk_indexes ++ policy_indexes ++ composite_indexes
  end
  
  defp analyze_policy_and_create_indexes(policy) do
    # Parse policy condition and suggest indexes
    condition = policy.condition
    
    cond do
      String.contains?(condition, "auth.uid() = ") ->
        # Extract field being compared to auth.uid()
        field = extract_auth_field(condition)
        quote do
          index [unquote(field)]
        end
        
      String.contains?(condition, "published = true") ->
        quote do
          index [:published]
        end
        
      true ->
        nil
    end
  end
  
  defp generate_composite_indexes(table) do
    # Common patterns for composite indexes
    timestamp_fields = Enum.filter(table.fields, &(&1.type == :timestamptz))
    
    if length(timestamp_fields) > 0 do
      [quote do
        index [:created_at, :updated_at]
      end]
    else
      []
    end
  end
end

# Apply to your schema
defmodule OptimizedSchema do
  use Tenjin.Schema
  import IndexOptimizer
  
  table "posts" do
    field :id, :uuid, primary_key: true
    field :title, :text
    field :author_id, :uuid, references: "users(id)"
    field :published, :boolean, default: false
    field :created_at, :timestamptz, default: "now()"
    
    enable_rls()
    
    policy :select, "Public can view published posts" do
      "published = true"
    end
    
    policy :select, "Authors can view their own posts" do
      "auth.uid() = author_id"
    end
    
    # Automatically generate optimal indexes
    auto_generate_indexes(__MODULE__)
  end
end
```

## 🏗️ Maintainability for Growing Projects

### Type-Safe Schema Evolution

Handle schema changes safely with deprecation warnings:

```elixir
defmodule SchemaEvolution do
  defmacro deprecate_field(field_name, replacement, opts \\ []) do
    version = opts[:since] || "next version"
    
    quote do
      @deprecated "#{unquote(field_name)} is deprecated since #{unquote(version)}. Use #{unquote(replacement)} instead."
      field unquote(field_name), :text
      
      # Add new field with migration path
      field unquote(replacement), :text
    end
  end
  
  defmacro add_field_with_migration(field_name, type, migration_fn) do
    quote do
      field unquote(field_name), unquote(type)
      
      # Store migration function for later use
      @field_migrations {unquote(field_name), unquote(migration_fn)}
    end
  end
end

defmodule UserSchema do
  use Tenjin.Schema
  import SchemaEvolution
  
  table "users" do
    field :id, :uuid, primary_key: true
    
    # Deprecate old field, introduce new one
    deprecate_field(:full_name, :display_name, since: "v2.0")
    
    # Add field with data migration
    add_field_with_migration(:preferences, :jsonb, &migrate_user_preferences/1)
  end
end
```

### Documentation Generation

Generate comprehensive documentation from schema definitions:

```elixir
defmodule SchemaDocs do
  def generate_docs(schema_module) do
    schema = schema_module.__schema__()
    
    """
    # Database Schema Documentation
    
    Generated from: #{schema_module}
    Generated on: #{DateTime.utc_now()}
    
    #{for table <- schema.tables, do: document_table(table)}
    """
  end
  
  defp document_table(table) do
    """
    ## Table: `#{table.name}`
    
    #{table.options[:comment] || "No description provided."}
    
    ### Fields
    
    | Field | Type | Constraints | Description |
    |-------|------|-------------|-------------|
    #{for field <- table.fields, do: document_field(field)}
    
    ### Row Level Security
    
    #{if table.rls_enabled, do: "✅ Enabled", else: "❌ Disabled"}
    
    #{if not Enum.empty?(table.policies) do
      """
      #### Policies
      
      #{for policy <- table.policies, do: document_policy(policy)}
      """
    end}
    
    ### Indexes
    
    #{for index <- table.indexes, do: document_index(index)}
    
    ---
    """
  end
  
  defp document_field(field) do
    constraints = []
    constraints = if field.options[:primary_key], do: ["PRIMARY KEY" | constraints], else: constraints
    constraints = if field.options[:unique], do: ["UNIQUE" | constraints], else: constraints
    constraints = if field.options[:null] == false, do: ["NOT NULL" | constraints], else: constraints
    constraints = if field.options[:references], do: ["FK: #{field.options[:references]}" | constraints], else: constraints
    
    constraint_text = if Enum.empty?(constraints), do: "-", else: Enum.join(constraints, ", ")
    
    "| `#{field.name}` | `#{field.type}` | #{constraint_text} | #{field.options[:comment] || "-"} |"
  end
  
  defp document_policy(policy) do
    """
    - **#{String.upcase(to_string(policy.action))}**: #{policy.description}
      ```sql
      #{policy.condition}
      ```
    """
  end
  
  defp document_index(index) do
    unique_text = if index.options[:unique], do: " (UNIQUE)", else: ""
    "- `#{Enum.join(index.fields, ", ")}`#{unique_text}"
  end
end

# Usage in your project
# File: lib/mix/tasks/docs.gen.ex
defmodule Mix.Tasks.Docs.Gen do
  use Mix.Task
  
  def run(_args) do
    docs = SchemaDocs.generate_docs(MyApp.Schema)
    File.write!("docs/database_schema.md", docs)
    Mix.shell().info("Generated database documentation at docs/database_schema.md")
  end
end
```

### Schema Testing Framework

Comprehensive testing for schema definitions:

```elixir
defmodule SchemaTestHelpers do
  defmacro test_schema(schema_module) do
    quote do
      test "#{unquote(schema_module)} compiles without errors" do
        assert function_exported?(unquote(schema_module), :__schema__, 0)
        schema = unquote(schema_module).__schema__()
        assert is_map(schema)
        assert is_list(schema.tables)
      end
      
      test "#{unquote(schema_module)} has valid foreign key references" do
        schema = unquote(schema_module).__schema__()
        assert SchemaValidator.validate_references(schema) == :ok
      end
      
      test "#{unquote(schema_module)} RLS policies are valid" do
        schema = unquote(schema_module).__schema__()
        assert SchemaValidator.validate_policy_conditions(schema) == :ok
      end
      
      test "#{unquote(schema_module)} generates valid SQL" do
        sql = Tenjin.Generator.Migration.generate_sql_content([unquote(schema_module)])
        assert is_binary(sql)
        assert String.length(sql) > 0
        # Could add SQL parsing validation here
      end
    end
  end
end

# Usage in your tests
defmodule MyApp.SchemaTest do
  use ExUnit.Case
  import SchemaTestHelpers
  
  test_schema(MyApp.Schema)
  test_schema(MyApp.UserManagement.Schema)
  test_schema(MyApp.Billing.Schema)
  
  test "schema evolution compatibility" do
    # Test that old and new schemas are compatible
    old_schema = load_schema_from_git("v1.0")
    new_schema = MyApp.Schema.__schema__()
    
    changes = SchemaDiff.compare(old_schema, new_schema)
    assert SchemaDiff.breaking_changes?(changes) == false
  end
end
```

### Modular Architecture

Organize large schemas into composable modules:

```elixir
# Domain-specific schema modules
defmodule UserManagement.Schema do
  use Tenjin.Schema
  
  table "users" do
    field :id, :uuid, primary_key: true
    field :email, :text, unique: true, null: false
    field :name, :text
    # ... user fields
  end
  
  table "user_profiles" do
    field :id, :uuid, primary_key: true
    field :user_id, :uuid, references: "users(id)", on_delete: :cascade
    # ... profile fields
  end
end

defmodule Billing.Schema do
  use Tenjin.Schema
  
  table "subscriptions" do
    field :id, :uuid, primary_key: true
    field :user_id, :uuid, references: "users(id)"
    # ... billing fields
  end
  
  table "invoices" do
    # ... invoice fields
  end
end

defmodule ContentManagement.Schema do
  use Tenjin.Schema
  
  table "posts" do
    field :id, :uuid, primary_key: true
    field :author_id, :uuid, references: "users(id)"
    # ... content fields
  end
end

# Main application schema that composes everything
defmodule MyApp.Schema do
  @moduledoc """
  Main application schema that combines all domain schemas.
  """
  
  # Import all domain schemas
  use UserManagement.Schema
  use Billing.Schema
  use ContentManagement.Schema
  
  # Add cross-domain relationships or global tables here
  table "audit_logs" do
    field :id, :uuid, primary_key: true
    field :user_id, :uuid, references: "users(id)"
    field :action, :text
    field :resource_type, :text
    field :resource_id, :uuid
    field :created_at, :timestamptz, default: "now()"
    
    enable_rls()
    
    policy :select, "Admins can view audit logs" do
      "auth.role() = 'admin'"
    end
  end
end
```

### Configuration-Driven Schema

Create flexible schemas based on external configuration:

```elixir
defmodule ConfigurableSchema do
  use Tenjin.Schema
  
  @schema_config Application.compile_env(:my_app, :schema_config)
  
  # Generate tables from configuration
  for table_config <- @schema_config.tables do
    table table_config.name do
      # Generate fields from config
      for field_config <- table_config.fields do
        field field_config.name, field_config.type, field_config.options || []
      end
      
      # Apply RLS if configured
      if table_config.rls_enabled do
        enable_rls()
        
        # Generate policies from config
        for policy_config <- table_config.policies || [] do
          policy policy_config.action, policy_config.description do
            policy_config.condition
          end
        end
      end
      
      # Generate indexes from config
      for index_config <- table_config.indexes || [] do
        index index_config.fields, index_config.options || []
      end
    end
  end
end

# Configuration file: config/schema.exs
import Config

config :my_app, :schema_config, %{
  tables: [
    %{
      name: "users",
      rls_enabled: true,
      fields: [
        %{name: :id, type: :uuid, options: [primary_key: true, default: "gen_random_uuid()"]},
        %{name: :email, type: :text, options: [unique: true, null: false]},
        %{name: :name, type: :text}
      ],
      policies: [
        %{action: :select, description: "Users can view own profile", condition: "auth.uid() = id"}
      ],
      indexes: [
        %{fields: [:email], options: [unique: true]}
      ]
    }
    # ... more tables
  ]
}
```

These advanced features demonstrate how Tenjin's Elixir-based approach enables sophisticated database schema management that scales with your application's complexity while maintaining type safety and developer productivity.