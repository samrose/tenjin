# Schema DSL Reference

Complete reference for Tenjin's Elixir DSL for defining database schemas.

## Table Definition

```elixir
table "table_name" do
  # field definitions
  # indexes
  # policies
  # triggers
end
```

## Field Types

### Basic Types
- `:text` - Variable length text
- `:integer` - 32-bit integer
- `:bigint` - 64-bit integer
- `:boolean` - Boolean true/false
- `:uuid` - UUID type
- `:timestamptz` - Timestamp with timezone
- `:date` - Date only
- `:numeric` - Arbitrary precision numeric
- `:jsonb` - JSON binary format

### Field Options
- `primary_key: true` - Mark as primary key
- `unique: true` - Add unique constraint
- `null: false` - Make field NOT NULL
- `default: "value"` - Set default value
- `references: "table(column)"` - Foreign key reference
- `on_delete: :cascade` - Foreign key cascade action

## Row Level Security (RLS)

### Enable RLS
```elixir
enable_rls()
```

### Policy Types
- `:select` - Controls read access
- `:insert` - Controls create access  
- `:update` - Controls modify access
- `:delete` - Controls delete access
- `:all` - Controls all operations

### Policy Definition
```elixir
policy :select, "Description" do
  "auth.uid() = user_id"
end
```

## Indexes

### Basic Index
```elixir
index [:column_name]
```

### Unique Index
```elixir
index [:column_name], unique: true
```

### Composite Index
```elixir
index [:column1, :column2]
```

### Partial Index
```elixir
index [:column], where: "active = true"
```

## Complete Example

```elixir
defmodule MyApp.Schema do
  use Tenjin.Schema

  table "users" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :email, :text, unique: true, null: false
    field :name, :text
    field :created_at, :timestamptz, default: "now()"

    enable_rls()

    policy :select, "Users can view their own profile" do
      "auth.uid() = id"
    end

    index [:email], unique: true
  end
end
```