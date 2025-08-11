defmodule Mix.Tasks.Tenjin.Migrate do
  @shortdoc "Applies pending database migrations"

  @moduledoc """
  Applies pending database migrations using Supabase CLI.

  This task runs `supabase db push` to apply all pending migrations
  in the `supabase/migrations` directory to the local database.

  ## Usage

      mix tenjin.migrate [options]

  ## Options

    * `--dry-run` - Show what would be applied without making changes
    * `--include-seed` - Include seed data after applying migrations

  ## Examples

      mix tenjin.migrate
      mix tenjin.migrate --dry-run
      mix tenjin.migrate --include-seed

  ## Prerequisites

  - Supabase must be running (start with `mix tenjin.supabase.start`)  
  - Migration files must exist in `supabase/migrations/`

  """

  use Mix.Task

  alias Tenjin.Generator.Migration
  alias Tenjin.Supabase.CLI

  @impl Mix.Task
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, 
      strict: [
        dry_run: :boolean, 
        include_seed: :boolean,
        local: :boolean
      ]
    )

    project_path = File.cwd!()
    
    # Validate we're in the right environment
    validate_environment!(project_path)

    if opts[:dry_run] do
      Mix.shell().info("🔍 Performing dry run (no changes will be made)...")
    else
      Mix.shell().info("🔄 Applying database migrations...")
    end

    # Check for pending migrations
    migrations = Migration.list_migration_files(project_path)
    
    if Enum.empty?(migrations) do
      Mix.shell().info("📝 No migration files found.")
      Mix.shell().info("Generate your first migration with: mix tenjin.gen.migration initial_schema")
    else
      # Show migration files
      Mix.shell().info("Found #{length(migrations)} migration file(s):")
      Enum.each(migrations, fn migration ->
        Mix.shell().info("  • #{migration.filename}")
      end)

      # Apply migrations with local flag (default to true for development)
      local_flag = Keyword.get(opts, :local, true)
      migration_opts = Keyword.put(opts, :local, local_flag)
      case Migration.apply_migrations(project_path, migration_opts) do
      {:ok, output} ->
        if opts[:dry_run] do
          Mix.shell().info("✅ Dry run completed successfully")
          if String.trim(output) != "" do
            Mix.shell().info("\nChanges that would be applied:")
            Mix.shell().info(output)
          else
            Mix.shell().info("No changes would be applied.")
          end
        else
          Mix.shell().info("✅ Migrations applied successfully")
          
          # Parse output for useful information
          if String.contains?(output, "already applied") do
            Mix.shell().info("All migrations were already applied.")
          end
          
          if String.contains?(output, "Applied") do
            applied_count = count_applied_migrations(output)
            Mix.shell().info("Applied #{applied_count} new migration(s).")
          end
        end

        # Optionally run seeds
        if opts[:include_seed] and not opts[:dry_run] do
          run_seeds(project_path)
        end

        # Show next steps
        unless opts[:dry_run] do
          print_next_steps()
        end

      {:error, {exit_code, error_output}} when is_integer(exit_code) ->
        Mix.shell().error("❌ Migration failed (exit code: #{exit_code}):")
        Mix.shell().error(error_output)
        
        # Provide helpful error messages
        cond do
          String.contains?(error_output, "connection refused") ->
            Mix.shell().error("\n💡 Database connection failed. Make sure Supabase is running:")
            Mix.shell().error("   mix tenjin.supabase.start")
          
          String.contains?(error_output, "syntax error") ->
            Mix.shell().error("\n💡 SQL syntax error in migration. Check your migration files.")
          
          String.contains?(error_output, "already exists") ->
            Mix.shell().error("\n💡 Schema object already exists. You might need to:")
            Mix.shell().error("   mix tenjin.supabase.reset  # Reset database")
            Mix.shell().error("   mix tenjin.migrate          # Reapply migrations")
            
          true ->
            Mix.shell().error("\n💡 Check the error above and fix any issues in your migrations.")
        end
        
        Mix.raise("Migration failed")

        {:error, reason} ->
          Mix.shell().error("❌ Migration failed: #{inspect(reason)}")
          Mix.raise("Migration failed")
      end
    end
  end

  defp validate_environment!(project_path) do
    # Check if we're in a Tenjin project
    unless File.exists?("mix.exs") and File.exists?("supabase/config.toml") do
      Mix.raise("Not in a Tenjin project with Supabase. Run 'mix tenjin.init' first.")
    end

    # Check if Supabase is running
    case CLI.status(cd: project_path) do
      {:ok, status} when is_map(status) ->
        unless status.running do
          Mix.raise("Supabase is not running. Start it with: mix tenjin.supabase.start")
        end
      {:error, reason} ->
        Mix.raise("Cannot connect to Supabase: #{inspect(reason)}")
    end
  end

  defp count_applied_migrations(output) do
    output
    |> String.split("\n")
    |> Enum.count(&String.contains?(&1, "Applied"))
  end

  defp run_seeds(project_path) do
    Mix.shell().info("🌱 Running seed files...")
    
    seeds_dir = Path.join([project_path, "priv", "seeds"])
    env = Mix.env() |> Atom.to_string()
    seed_file = Path.join(seeds_dir, "#{env}.exs")
    
    if File.exists?(seed_file) do
      Mix.shell().info("Running seeds from: #{seed_file}")
      
      # This is a simplified seed runner - in a real implementation,
      # you'd want to set up proper database connection and context
      try do
        Code.eval_file(seed_file)
        Mix.shell().info("✅ Seeds completed successfully")
      rescue
        error ->
          Mix.shell().error("❌ Seed failed: #{Exception.message(error)}")
          Mix.shell().error("Fix the seed file and run: mix tenjin.seed")
      end
    else
      Mix.shell().info("No seed file found at: #{seed_file}")
      Mix.shell().info("Create seed files in priv/seeds/ directory")
    end
  end

  defp print_next_steps do
    Mix.shell().info("""

    🎉 Database is up to date!

    Next steps:
      📊 Explore your database: Visit Supabase Studio (check output from 'mix tenjin.supabase.start')
      🔧 Generate TypeScript types: mix tenjin.gen.types  
      🌱 Run seed data: mix tenjin.seed
      🚀 Start your application: mix tenjin.server

    Development workflow:
      1. Update your schema in lib/*/schema.ex
      2. Generate migration: mix tenjin.gen.migration <name>
      3. Apply migration: mix tenjin.migrate
      4. Repeat as needed!
    """)
  end
end
