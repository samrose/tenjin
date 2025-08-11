defmodule Mix.Tasks.Tenjin.Gen.Migration do
  @shortdoc "Generates a database migration from Tenjin schema"

  @moduledoc """
  Generates a database migration from Tenjin schema definitions.

  This task integrates with Supabase CLI to create migration files and 
  populates them with SQL generated from your Elixir schema definitions.

  ## Usage

      mix tenjin.gen.migration <migration_name> [options]

  ## Options

    * `--diff` - Generate migration using `supabase db diff` (compares with current DB state)
    * `--schema` - Only include specific schema (for diff mode)
    * `--exclude-schema` - Exclude specific schema (for diff mode)

  ## Examples

      # Generate migration from current schema definitions
      mix tenjin.gen.migration create_users_table

      # Generate migration using database diff
      mix tenjin.gen.migration add_posts_table --diff

      # Generate diff migration for specific schema only
      mix tenjin.gen.migration update_auth --diff --schema auth

  The generated migration file will be placed in `supabase/migrations/` and
  can be applied using `mix tenjin.migrate`.
  """

  use Mix.Task
  
  alias Tenjin.Generator.Migration
  alias Tenjin.Supabase.CLI

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args,
      strict: [
        diff: :boolean,
        schema: :string,
        exclude_schema: :string
      ]
    ) do
      {opts, [migration_name], []} ->
        generate_migration(migration_name, opts)
      {_opts, [], []} ->
        Mix.raise("Expected migration name to be given, got: mix tenjin.gen.migration")
      {_opts, _args, []} ->
        Mix.raise("Expected a single migration name, got multiple arguments")
      {_opts, _args, invalid} ->
        Mix.raise("Invalid options: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")
    end
  end

  defp generate_migration(migration_name, opts) do
    project_path = File.cwd!()
    
    # Validate we're in a Tenjin project
    validate_tenjin_project!()
    
    # Validate Supabase is available
    validate_supabase_environment!(project_path)

    Mix.shell().info("Generating migration: #{migration_name}")

    if opts[:diff] do
      generate_diff_migration(project_path, migration_name, opts)
    else
      generate_schema_migration(project_path, migration_name, opts)
    end
  end

  defp generate_schema_migration(project_path, migration_name, _opts) do
    # Get configured schema modules
    schema_modules = get_schema_modules()

    if Enum.empty?(schema_modules) do
      Mix.shell().info("No schema modules configured. Creating empty migration.")
      
      case CLI.db_new_migration(migration_name, cd: project_path) do
        {:ok, output} ->
          Mix.shell().info("Created empty migration: #{extract_filename(output)}")
          Mix.shell().info("Edit the migration file to add your SQL statements.")
        {:error, reason} ->
          Mix.raise("Failed to create migration: #{inspect(reason)}")
      end
    else
      # Generate migration with SQL content from schema modules
      Mix.shell().info("Generating SQL from schema modules: #{inspect(schema_modules)}")
      
      case Migration.create_migration(project_path, migration_name, schema_modules) do
        {:ok, migration} ->
          filename = Path.basename(migration.file_path)
          Mix.shell().info("Created migration: #{filename}")
          
          # Show migration content preview
          if Mix.shell().yes?("Show generated SQL preview?") do
            Mix.shell().info("\n--- Generated SQL ---")
            Mix.shell().info(migration.content)
            Mix.shell().info("--- End SQL ---\n")
          end
          
          Mix.shell().info("Apply the migration with: mix tenjin.migrate")
          
        {:error, reason} ->
          Mix.raise("Failed to generate migration: #{inspect(reason)}")
      end
    end
  end

  defp generate_diff_migration(project_path, migration_name, opts) do
    Mix.shell().info("Generating migration using database diff...")
    
    # Ensure database is running
    case CLI.status(cd: project_path) do
      {:ok, status} when is_map(status) ->
        if status.running do
          Mix.shell().info("Database is running, generating diff...")
        else
          Mix.raise("Database is not running. Start it with: mix tenjin.supabase.start")
        end
      {:error, _} ->
        Mix.raise("Cannot connect to database. Ensure Supabase is running.")
    end

    case Migration.create_diff_migration(project_path, migration_name, opts) do
      {:ok, migration} ->
        filename = Path.basename(migration.file_path)
        Mix.shell().info("Created diff migration: #{filename}")
        
        if String.trim(migration.content) == "" do
          Mix.shell().info("No changes detected between database and current state.")
        else
          # Show migration content
          if Mix.shell().yes?("Show generated diff SQL?") do
            Mix.shell().info("\n--- Generated Diff SQL ---")
            Mix.shell().info(migration.content)
            Mix.shell().info("--- End SQL ---\n")
          end
          
          Mix.shell().info("Apply the migration with: mix tenjin.migrate")
        end
        
      {:error, reason} ->
        Mix.raise("Failed to generate diff migration: #{inspect(reason)}")
    end
  end

  defp get_schema_modules do
    # Get schema modules from application config
    case Application.get_env(:tenjin, :schema_modules) do
      modules when is_list(modules) and length(modules) > 0 ->
        # Ensure modules are loaded
        Enum.map(modules, fn module ->
          case Code.ensure_loaded(module) do
            {:module, loaded_module} -> loaded_module
            {:error, reason} ->
              Mix.raise("Failed to load schema module #{module}: #{reason}")
          end
        end)
      
      _ ->
        # Try to find schema modules automatically
        find_schema_modules()
    end
  end

  defp find_schema_modules do
    # Look for modules that use Tenjin.Schema
    Mix.shell().info("Searching for schema modules...")
    
    # First ensure the project is compiled
    case Mix.Task.run("compile") do
      :ok -> :ok
      :noop -> :ok
      _ -> Mix.shell().info("Warning: Compilation may have failed, continuing anyway")
    end
    
    _app_name = Mix.Project.config()[:app]
    
    # Search in lib/{app_name}/ for schema files
    schema_files = 
      ["lib/**/schema.ex", "lib/**/*_schema.ex"]
      |> Enum.flat_map(&Path.wildcard/1)
    
    schema_modules = 
      schema_files
      |> Enum.map(&extract_module_from_file/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&implements_tenjin_schema?/1)
    
    if Enum.empty?(schema_modules) do
      Mix.shell().info("No Tenjin schema modules found.")
      Mix.shell().info("Create a schema module using 'use Tenjin.Schema' or configure :schema_modules in config.exs")
    else
      Mix.shell().info("Found schema modules: #{inspect(schema_modules)}")
    end
    
    schema_modules
  end

  defp extract_module_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Regex.run(~r/defmodule\s+([A-Z][A-Za-z0-9_.]*)\s+do/, content) do
          [_, module_name] ->
            try do
              # Try to create the atom (this will work even if module isn't loaded yet)
              module_atom = String.to_atom("Elixir.#{module_name}")
              
              # Try to load the module
              case Code.ensure_loaded(module_atom) do
                {:module, ^module_atom} -> module_atom
                {:error, _} -> 
                  # Module exists in file but not compiled yet, try to compile it
                  case Code.compile_file(file_path) do
                    modules when is_list(modules) ->
                      # Return the first module that matches our expected name
                      Enum.find_value(modules, fn {mod, _bytecode} ->
                        if mod == module_atom, do: mod, else: nil
                      end)
                    _ -> nil
                  end
              end
            rescue
              _ -> nil
            end
          _ -> nil
        end
      {:error, _} -> nil
    end
  end

  defp implements_tenjin_schema?(module) do
    try do
      # Ensure module is loaded first
      case Code.ensure_loaded(module) do
        {:module, ^module} ->
          # Check if module has the required Tenjin.Schema functions
          function_exported?(module, :__schema__, 0) and
          function_exported?(module, :__tables__, 0)
        {:error, _} -> false
      end
    rescue
      _ -> false
    end
  end

  defp validate_tenjin_project! do
    unless File.exists?("mix.exs") do
      Mix.raise("Not in a Mix project. Please run this command from a project root.")
    end

    mix_exs_content = File.read!("mix.exs")
    unless String.contains?(mix_exs_content, ":tenjin") do
      Mix.raise("This doesn't appear to be a Tenjin project. Add {:tenjin, \"~> 0.1.0\"} to your deps in mix.exs")
    end
  end

  defp validate_supabase_environment!(project_path) do
    # Check if Supabase CLI is available
    case CLI.check_installation() do
      {:ok, version} ->
        Mix.shell().info("Using Supabase CLI: #{version}")
      {:error, :not_installed} ->
        Mix.raise("Supabase CLI is not installed. Please install it first: https://supabase.com/docs/guides/cli")
      {:error, reason} ->
        Mix.raise("Supabase CLI error: #{inspect(reason)}")
    end

    # Check if we're in a Supabase project
    unless CLI.in_project?(cd: project_path) do
      Mix.raise("Not in a Supabase project. Initialize with: mix tenjin.init")
    end
  end

  defp extract_filename(output) do
    case Regex.run(~r/supabase\/migrations\/(.+\.sql)/, output) do
      [_, filename] -> filename
      _ -> "migration file"
    end
  end
end
