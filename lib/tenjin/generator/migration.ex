defmodule Tenjin.Generator.Migration do
  @moduledoc """
  Migration generation system for Tenjin framework.
  
  This module integrates with Supabase CLI's migration system:
  
  1. Uses `supabase migration new <name>` to create migration files
  2. Translates Tenjin Elixir DSL to SQL content for those files  
  3. Uses `supabase db diff` to generate incremental migrations
  4. Uses `supabase db push` to apply migrations
  
  The workflow:
  - Tenjin generates SQL content from Elixir schema definitions
  - Supabase CLI handles file management and database operations
  """

  alias Tenjin.Generator.{SQL, RLS}
  alias Tenjin.Supabase.CLI

  @doc """
  Creates a new migration using Supabase CLI and populates it with SQL from schema.
  
  This function:
  1. Uses `supabase migration new <name>` to create the migration file
  2. Generates SQL content from Tenjin schema modules
  3. Writes the SQL content to the created migration file
  """
  def create_migration(project_path, migration_name, schema_modules, opts \\ []) do
    # Create migration file directly with timestamp (avoid hanging Supabase CLI)
    now = DateTime.utc_now()
    timestamp = "#{now.year}#{String.pad_leading(to_string(now.month), 2, "0")}#{String.pad_leading(to_string(now.day), 2, "0")}#{String.pad_leading(to_string(now.hour), 2, "0")}#{String.pad_leading(to_string(now.minute), 2, "0")}#{String.pad_leading(to_string(now.second), 2, "0")}"
    
    migration_filename = "#{timestamp}_#{migration_name}.sql"
    migrations_dir = Path.join([project_path, "supabase", "migrations"])
    migration_file_path = Path.join(migrations_dir, migration_filename)
    
    # Ensure migrations directory exists
    case File.mkdir_p(migrations_dir) do
      :ok ->
        # Generate SQL content from schema modules
        sql_content = generate_sql_content(schema_modules, opts)
        
        # Write SQL content to the migration file
        case File.write(migration_file_path, sql_content) do
          :ok ->
            {:ok, %{
              file_path: migration_file_path,
              name: migration_name,
              content: sql_content
            }}
          {:error, reason} ->
            {:error, {:write_failed, reason}}
        end
      {:error, reason} ->
        {:error, {:mkdir_failed, reason}}
    end
  end

  @doc """
  Generates a database diff migration using Supabase CLI.
  
  This uses `supabase db diff <name>` to automatically generate a migration
  by comparing the current schema with the database state.
  """
  def create_diff_migration(project_path, migration_name, _opts \\ []) do
    # Use Supabase CLI to generate diff
    case CLI.db_diff(migration_name, cd: project_path) do
      {:ok, output} ->
        case extract_migration_path_from_output(output, project_path) do
          {:ok, migration_file_path} ->
            {:ok, content} = File.read(migration_file_path)
            {:ok, %{
              file_path: migration_file_path,
              name: migration_name,
              content: content,
              generated_by: :supabase_diff
            }}
          {:error, reason} ->
            {:error, {:migration_path_not_found, reason}}
        end
      {:error, reason} ->
        {:error, {:supabase_diff_failed, reason}}
    end
  end

  @doc """
  Generates SQL content from Tenjin schema modules for initial migration.
  """
  def generate_sql_content(schema_modules, opts \\ []) when is_list(schema_modules) do
    description = opts[:description] || "Tenjin schema migration"
    
    # Generate all schema elements from modules
    up_statements = 
      schema_modules
      |> Enum.flat_map(fn module ->
        schema = module.__schema__()
        
        # Custom types first (they may be referenced by tables)
        type_statements = Enum.map(schema.custom_types, &SQL.generate_custom_type/1)
        
        # Tables and their components  
        table_statements = generate_table_statements(schema.tables)
        
        # Functions
        function_statements = Enum.map(schema.functions, &SQL.generate_function/1)
        
        # Views
        view_statements = Enum.map(schema.views, &SQL.generate_view/1)
        
        # Storage buckets
        bucket_statements = generate_storage_bucket_statements(schema.storage_buckets)

        type_statements ++ table_statements ++ function_statements ++ view_statements ++ bucket_statements
      end)
      |> Enum.reject(&(&1 == "" or &1 == nil))

    format_migration_sql(description, up_statements)
  end

  defp generate_table_statements(tables) do
    tables
    |> Enum.flat_map(fn table ->
      statements = []
      
      # Create table
      table_sql = SQL.generate_table(table)
      statements = [table_sql | statements]
      
      # Enable RLS if needed
      statements = if table.rls_enabled do
        rls_sql = SQL.enable_rls(table.name)
        [rls_sql | statements]
      else
        statements
      end
      
      # Generate RLS policies
      statements = if table.rls_enabled and not Enum.empty?(table.policies) do
        policies_sql = RLS.generate_policies(table)
        [policies_sql | statements]
      else
        statements
      end
      
      # Generate indexes
      statements = if not Enum.empty?(table.indexes) do
        indexes_sql = SQL.generate_indexes(table)
        [indexes_sql | statements]
      else
        statements
      end
      
      # Generate triggers
      statements = if not Enum.empty?(table.triggers) do
        triggers_sql = SQL.generate_triggers(table)
        [triggers_sql | statements]
      else
        statements
      end
      
      Enum.reverse(statements)
    end)
  end

  defp generate_storage_bucket_statements(buckets) do
    buckets
    |> Enum.flat_map(fn bucket ->
      bucket_sql = SQL.generate_storage_bucket(bucket)
      policy_sqls = Enum.map(bucket.policies, &RLS.generate_storage_policy(bucket.name, &1))
      [bucket_sql | policy_sqls]
    end)
  end

  defp extract_migration_path_from_output(output, project_path) do
    # Parse Supabase CLI output to find migration file path
    case Regex.run(~r/Created new migration at (.+\.sql)/, output) do
      [_, relative_path] ->
        # Convert to absolute path
        full_path = Path.expand(relative_path, project_path)
        {:ok, full_path}
      _ ->
        # Try alternative pattern
        case Regex.run(~r/supabase\/migrations\/(.+\.sql)/, output) do
          [_, filename] ->
            full_path = Path.join([project_path, "supabase", "migrations", filename])
            {:ok, full_path}
          _ ->
            {:error, "Could not extract migration path from output: #{output}"}
        end
    end
  end

  defp format_migration_sql(description, statements) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    
    sql_content = 
      statements
      |> Enum.join("\n\n")

    """
    -- #{description}
    -- Created: #{timestamp}
    -- Generated by: Tenjin Framework

    #{sql_content}
    """
  end

  @doc """
  Applies migrations using Supabase CLI.
  """
  def apply_migrations(project_path, _opts \\ []) do
    CLI.db_push(cd: project_path)
  end

  @doc """
  Resets database and reapplies all migrations using Supabase CLI.
  """
  def reset_and_migrate(project_path, _opts \\ []) do
    CLI.reset_db(cd: project_path)
  end

  @doc """
  Lists existing migration files in the Supabase migrations directory.
  """
  def list_migration_files(project_path) do
    migrations_dir = Path.join([project_path, "supabase", "migrations"])
    
    if File.exists?(migrations_dir) do
      migrations_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".sql"))
      |> Enum.sort()
      |> Enum.map(fn filename ->
        full_path = Path.join(migrations_dir, filename)
        %{
          filename: filename,
          path: full_path,
          timestamp: extract_timestamp_from_filename(filename)
        }
      end)
    else
      []
    end
  end

  defp extract_timestamp_from_filename(filename) do
    case Regex.run(~r/^(\d{14})/, filename) do
      [_, timestamp] -> timestamp
      _ -> nil
    end
  end
end
