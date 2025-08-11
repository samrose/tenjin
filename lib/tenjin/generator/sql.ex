defmodule Tenjin.Generator.SQL do
  @moduledoc """
  SQL generation from Tenjin schema definitions.
  
  This module converts Tenjin DSL definitions into PostgreSQL DDL statements.
  """

  alias Tenjin.Types

  @doc """
  Generates CREATE TABLE statement from table definition.
  """
  def generate_table(%{name: name, fields: fields, options: opts}) do
    fields_sql = 
      fields
      |> Enum.reverse() # Reverse since fields are accumulated in reverse order
      |> Enum.map(&generate_field/1)
      |> add_primary_key()
      |> Enum.join(",\n  ")

    comment_sql = case opts[:comment] do
      nil -> ""
      comment -> "\nCOMMENT ON TABLE #{name} IS #{escape_string(comment)};"
    end

    """
    CREATE TABLE #{name} (
      #{fields_sql}
    );#{comment_sql}
    """
  end

  @doc """
  Generates field definition SQL.
  """
  def generate_field(%{name: name, type: type, options: opts}) do
    type_sql = Types.to_sql_type(type)
    constraints = generate_field_constraints(opts)
    
    "#{name} #{type_sql}#{constraints}"
  end

  defp generate_field_constraints(opts) do
    constraints = []
    
    constraints = if opts[:primary_key] do
      [" PRIMARY KEY" | constraints]
    else
      constraints
    end
    
    constraints = if opts[:null] == false do
      [" NOT NULL" | constraints]
    else
      constraints
    end

    constraints = if opts[:unique] do
      [" UNIQUE" | constraints]
    else
      constraints
    end

    constraints = case opts[:default] do
      nil -> constraints
      default -> [" DEFAULT #{format_default_value(default)}" | constraints]
    end

    constraints = case opts[:references] do
      nil -> constraints
      ref -> [" REFERENCES #{ref}" | add_foreign_key_actions(opts) ++ constraints]
    end

    constraints = case opts[:generated] do
      nil -> constraints
      expr -> [" GENERATED ALWAYS AS (#{expr}) STORED" | constraints]
    end

    Enum.join(constraints)
  end

  defp add_foreign_key_actions(opts) do
    actions = []
    
    actions = case opts[:on_delete] do
      nil -> actions
      :cascade -> [" ON DELETE CASCADE" | actions]
      :restrict -> [" ON DELETE RESTRICT" | actions]
      :set_null -> [" ON DELETE SET NULL" | actions]
      :set_default -> [" ON DELETE SET DEFAULT" | actions]
    end

    actions = case opts[:on_update] do
      nil -> actions
      :cascade -> [" ON UPDATE CASCADE" | actions]
      :restrict -> [" ON UPDATE RESTRICT" | actions]
      :set_null -> [" ON UPDATE SET NULL" | actions]
      :set_default -> [" ON UPDATE SET DEFAULT" | actions]
    end

    actions
  end

  defp add_primary_key(fields_sql) do
    primary_keys = 
      fields_sql
      |> Enum.with_index()
      |> Enum.filter(fn {field_sql, _idx} -> 
        String.contains?(field_sql, "PRIMARY KEY") 
      end)
      |> Enum.map(fn {field_sql, _idx} -> 
        field_sql |> String.split() |> hd()
      end)

    case primary_keys do
      [] -> fields_sql
      [_single] -> fields_sql  # Single primary key is handled in field constraints
      multiple -> 
        # Remove PRIMARY KEY from individual fields and add composite constraint
        cleaned_fields = Enum.map(fields_sql, fn field ->
          String.replace(field, ~r/\s+PRIMARY KEY/, "")
        end)
        
        pk_constraint = "PRIMARY KEY (#{Enum.join(multiple, ", ")})"
        cleaned_fields ++ [pk_constraint]
    end
  end

  defp format_default_value(value) when is_binary(value) do
    cond do
      # Function calls like "gen_random_uuid()", "now()"
      String.ends_with?(value, "()") -> value
      # SQL expressions
      String.contains?(value, "(") or String.contains?(value, " ") -> value
      # String literals
      true -> "'#{value}'"
    end
  end

  defp format_default_value(value) when is_number(value), do: to_string(value)
  defp format_default_value(value) when is_boolean(value), do: to_string(value)
  defp format_default_value(value), do: "'#{value}'"

  @doc """
  Generates CREATE INDEX statements from table definition.
  """
  def generate_indexes(%{name: table_name, indexes: indexes}) do
    indexes
    |> Enum.reverse()
    |> Enum.map(&generate_index(table_name, &1))
    |> Enum.join("\n")
  end

  defp generate_index(table_name, %{fields: fields, options: opts}) do
    index_name = opts[:name] || generate_index_name(table_name, fields, opts)
    unique = if opts[:unique], do: "UNIQUE ", else: ""
    using = case opts[:using] do
      nil -> ""
      method -> " USING #{method}"
    end
    
    fields_str = Enum.join(fields, ", ")
    where_clause = case opts[:where] do
      nil -> ""
      condition -> " WHERE #{condition}"
    end

    comment_sql = case opts[:comment] do
      nil -> ""
      comment -> "\nCOMMENT ON INDEX #{index_name} IS #{escape_string(comment)};"
    end

    """
    CREATE #{unique}INDEX #{index_name} ON #{table_name}#{using} (#{fields_str})#{where_clause};#{comment_sql}
    """
  end

  defp generate_index_name(table_name, fields, opts) do
    suffix = if opts[:unique], do: "unique", else: "idx"
    fields_str = fields |> Enum.join("_")
    "#{table_name}_#{fields_str}_#{suffix}"
  end

  @doc """
  Generates trigger statements from table definition.
  """
  def generate_triggers(%{name: table_name, triggers: triggers}) do
    triggers
    |> Enum.reverse()
    |> Enum.map(&generate_trigger(table_name, &1))
    |> Enum.join("\n\n")
  end

  defp generate_trigger(table_name, %{name: trigger_name, events: events, body: body, options: opts}) do
    function_name = "#{table_name}_#{trigger_name}_trigger_fn"
    
    events_str = 
      events 
      |> Enum.map(&String.upcase(to_string(&1)))
      |> Enum.join(" OR ")
    
    timing = opts[:timing] || "BEFORE"
    for_each = opts[:for_each] || "ROW"
    when_clause = case opts[:when] do
      nil -> ""
      condition -> " WHEN (#{condition})"
    end

    function_sql = """
    CREATE OR REPLACE FUNCTION #{function_name}()
    RETURNS TRIGGER AS $$
    BEGIN
      #{body}
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    trigger_sql = """
    CREATE TRIGGER #{trigger_name}
      #{timing} #{events_str} ON #{table_name}
      FOR EACH #{String.upcase(for_each)}#{when_clause}
      EXECUTE FUNCTION #{function_name}();
    """

    function_sql <> "\n" <> trigger_sql
  end

  @doc """
  Generates database function definitions.
  """
  def generate_function(%{name: name, args: args, return_type: return_type, body: body, options: opts}) do
    args_sql = 
      args
      |> Enum.with_index(1)
      |> Enum.map(fn {type, idx} -> "$#{idx} #{Types.to_sql_type(type)}" end)
      |> Enum.join(", ")

    language = opts[:language] || "plpgsql"
    volatility = case opts[:volatility] do
      :immutable -> " IMMUTABLE"
      :stable -> " STABLE" 
      :volatile -> " VOLATILE"
      nil -> ""
    end

    security = case opts[:security] do
      :definer -> " SECURITY DEFINER"
      :invoker -> " SECURITY INVOKER"
      nil -> ""
    end

    """
    CREATE OR REPLACE FUNCTION #{name}(#{args_sql})
    RETURNS #{return_type}#{volatility}#{security} AS $$
    BEGIN
      #{body}
    END;
    $$ LANGUAGE #{language};
    """
  end

  @doc """
  Generates database view definitions.
  """
  def generate_view(%{name: name, query: query, options: opts}) do
    materialized = if opts[:materialized], do: "MATERIALIZED ", else: ""
    
    comment_sql = case opts[:comment] do
      nil -> ""
      comment -> "\nCOMMENT ON VIEW #{name} IS #{escape_string(comment)};"
    end

    """
    CREATE #{materialized}VIEW #{name} AS
    #{query};#{comment_sql}
    """
  end

  @doc """
  Generates custom type definitions.
  """
  def generate_custom_type(%{name: name, type: :enum, options: opts}) do
    values = 
      opts[:values]
      |> Enum.map(&"'#{&1}'")
      |> Enum.join(", ")

    "CREATE TYPE #{name} AS ENUM (#{values});"
  end

  def generate_custom_type(%{name: name, type: :composite, options: opts}) do
    fields = 
      opts[:fields]
      |> Enum.map(fn {field_name, field_type} -> 
        "#{field_name} #{Types.to_sql_type(field_type)}"
      end)
      |> Enum.join(", ")

    "CREATE TYPE #{name} AS (#{fields});"
  end

  def generate_custom_type(%{name: name, type: :domain, options: opts}) do
    base_type = Types.to_sql_type(opts[:base_type])
    constraint = case opts[:constraint] do
      nil -> ""
      expr -> " CONSTRAINT #{name}_check CHECK (#{expr})"
    end

    "CREATE DOMAIN #{name} AS #{base_type}#{constraint};"
  end

  @doc """
  Generates RLS enable statement.
  """
  def enable_rls(table_name) do
    "ALTER TABLE #{table_name} ENABLE ROW LEVEL SECURITY;"
  end

  @doc """
  Generates storage bucket creation SQL.
  """
  def generate_storage_bucket(%{name: name, options: opts}) do
    public = if opts[:public], do: "true", else: "false"
    
    file_size_limit = case opts[:file_size_limit] do
      nil -> "NULL"
      limit -> 
        case Types.parse_file_size(limit) do
          {:ok, bytes} -> to_string(bytes)
          {:error, _} -> "NULL"
        end
    end

    allowed_mime_types = case opts[:allowed_mime_types] do
      nil -> "NULL"
      types -> "ARRAY[#{types |> Enum.map(&"'#{&1}'") |> Enum.join(", ")}]"
    end

    """
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('#{name}', '#{name}', #{public}, #{file_size_limit}, #{allowed_mime_types})
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;
    """
  end

  defp escape_string(str) do
    "'#{String.replace(str, "'", "''")}'"
  end
end
