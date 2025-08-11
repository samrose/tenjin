defmodule Mix.Tasks.Tenjin.Sql.Generate do
  @shortdoc "Generates SQL from Tenjin schema definitions"

  @moduledoc """
  Generates SQL statements from Tenjin schema definitions without creating migrations.

  This task is useful for:
  - Previewing SQL that would be generated
  - Exporting schema definitions to SQL files
  - Debugging schema definitions
  - Integration with external tools

  ## Usage

      mix tenjin.sql.generate [options]

  ## Options

    * `--output <file>` - Write SQL to specified file instead of stdout
    * `--module <module>` - Generate SQL for specific schema module only
    * `--format <format>` - Output format: sql (default), json, yaml

  ## Examples

      # Generate SQL to stdout
      mix tenjin.sql.generate

      # Write SQL to file
      mix tenjin.sql.generate --output schema.sql

      # Generate SQL for specific module
      mix tenjin.sql.generate --module MyApp.UserSchema

      # Generate as JSON
      mix tenjin.sql.generate --format json

  """

  use Mix.Task

  alias Tenjin.Generator.Migration

  @impl Mix.Task
  def run(args) do
    {opts, [], []} = OptionParser.parse(args,
      strict: [
        output: :string,
        module: :string,
        format: :string
      ]
    )

    # Validate we're in a Tenjin project
    validate_tenjin_project!()

    Mix.shell().info("📝 Generating SQL from Tenjin schema definitions...")

    # Get schema modules
    schema_modules = get_schema_modules(opts[:module])

    if Enum.empty?(schema_modules) do
      Mix.shell().info("⚠️  No schema modules found.")
      Mix.shell().info("Create a schema module or configure :schema_modules in config.exs")
    else
      Mix.shell().info("Processing schema modules: #{inspect(schema_modules)}")

      # Generate SQL content
      sql_content = Migration.generate_sql_content(schema_modules, 
        description: "Generated SQL from Tenjin schema definitions"
      )

      # Format output based on requested format
      output_content = format_output(sql_content, schema_modules, opts[:format] || "sql")

      # Write output
      case opts[:output] do
        nil ->
          # Write to stdout
          IO.puts(output_content)
        
        output_file ->
          # Write to file
          case File.write(output_file, output_content) do
            :ok ->
              Mix.shell().info("✅ SQL written to: #{output_file}")
            {:error, reason} ->
              Mix.raise("Failed to write to #{output_file}: #{inspect(reason)}")
          end
      end

      # Show summary
      print_summary(schema_modules, sql_content)
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

  defp get_schema_modules(specific_module) when is_binary(specific_module) do
    try do
      module_atom = String.to_existing_atom("Elixir.#{specific_module}")
      case Code.ensure_loaded(module_atom) do
        {:module, loaded_module} -> 
          if implements_tenjin_schema?(loaded_module) do
            [loaded_module]
          else
            Mix.raise("Module #{specific_module} does not implement Tenjin.Schema")
          end
        {:error, reason} ->
          Mix.raise("Failed to load module #{specific_module}: #{reason}")
      end
    rescue
      ArgumentError ->
        Mix.raise("Module #{specific_module} not found")
    end
  end

  defp get_schema_modules(nil) do
    # Get all schema modules
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
    Mix.shell().info("🔍 Searching for schema modules...")
    
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
              String.to_existing_atom("Elixir.#{module_name}")
            rescue
              ArgumentError -> nil
            end
          _ -> nil
        end
      {:error, _} -> nil
    end
  end

  defp implements_tenjin_schema?(module) do
    try do
      # Check if module has the required Tenjin.Schema functions
      function_exported?(module, :__schema__, 0) and
      function_exported?(module, :__tables__, 0)
    rescue
      _ -> false
    end
  end

  defp format_output(sql_content, _schema_modules, "sql"), do: sql_content

  defp format_output(sql_content, schema_modules, "json") do
    data = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      generator: "Tenjin Framework",
      schema_modules: Enum.map(schema_modules, &to_string/1),
      sql_content: sql_content,
      schema_definitions: get_schema_definitions(schema_modules)
    }
    Jason.encode!(data, pretty: true)
  end

  defp format_output(sql_content, schema_modules, "yaml") do
    # Simple YAML output - in production you might want to use a proper YAML library
    """
    generated_at: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    generator: "Tenjin Framework"
    schema_modules:
    #{Enum.map_join(schema_modules, "\n", fn mod -> "  - #{mod}" end)}
    
    sql_content: |
    #{String.replace(sql_content, "\n", "\n  ")}
    """
  end

  defp format_output(_sql_content, _schema_modules, format) do
    Mix.raise("Unsupported format: #{format}. Supported formats: sql, json, yaml")
  end

  defp get_schema_definitions(schema_modules) do
    Enum.into(schema_modules, %{}, fn module ->
      schema = module.__schema__()
      {to_string(module), %{
        tables: length(schema.tables),
        functions: length(schema.functions),
        views: length(schema.views),
        storage_buckets: length(schema.storage_buckets),
        custom_types: length(schema.custom_types)
      }}
    end)
  end

  defp print_summary(schema_modules, sql_content) do
    # Count SQL statements
    sql_lines = String.split(sql_content, "\n")
    create_table_count = Enum.count(sql_lines, &String.contains?(&1, "CREATE TABLE"))
    create_function_count = Enum.count(sql_lines, &String.contains?(&1, "CREATE FUNCTION"))
    create_view_count = Enum.count(sql_lines, &String.contains?(&1, "CREATE VIEW"))
    create_policy_count = Enum.count(sql_lines, &String.contains?(&1, "CREATE POLICY"))

    Mix.shell().info("""

    📊 Generation Summary:
      Schema modules:  #{length(schema_modules)}
      Tables created:  #{create_table_count}
      Functions:       #{create_function_count}
      Views:           #{create_view_count}
      RLS policies:    #{create_policy_count}
      Total SQL lines: #{length(sql_lines)}
    """)
  end
end
