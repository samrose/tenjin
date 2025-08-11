defmodule Tenjin.Integration.WorkflowTest do
  @moduledoc """
  Integration tests for the complete Tenjin workflow.
  
  These tests simulate the full developer experience:
  1. Creating a new project
  2. Defining schemas
  3. Generating migrations
  4. Starting Supabase
  5. Applying migrations
  
  Note: These tests require Docker and Supabase CLI to be available.
  They are tagged with :integration and can be excluded in CI if needed.
  """
  
  use ExUnit.Case
  import Tenjin.TestHelpers

  @moduletag :integration
  @moduletag timeout: 120_000  # 2 minutes for integration tests

  describe "full Tenjin workflow" do
    setup do
      # Create a temporary project for integration testing
      project_path = create_tmp_project("integration_test")
      create_supabase_project(project_path)
      
      # Ensure cleanup on exit
      on_exit(fn -> 
        cleanup_tmp_dir(project_path)
        
        # Also cleanup any Supabase processes if they're running
        try do
          System.cmd("supabase", ["stop"], cd: project_path, stderr_to_stdout: true)
        rescue
          _ -> :ok  # Ignore errors during cleanup
        end
      end)
      
      %{project_path: project_path}
    end

    @tag :slow
    test "complete project lifecycle", %{project_path: project_path} do
      # Skip if Supabase CLI is not available
      unless supabase_cli_available?() do
        ExUnit.skip("Supabase CLI not available")
      end
      
      # Skip if Docker is not available
      unless docker_available?() do
        ExUnit.skip("Docker not available")
      end

      # Step 1: Create project structure (already done in setup)
      assert File.exists?(Path.join(project_path, "mix.exs"))
      assert File.exists?(Path.join(project_path, "supabase/config.toml"))

      # Step 2: Define schema (create a test schema file)
      schema_content = """
      defmodule IntegrationTest.Schema do
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

        table "posts" do
          field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
          field :title, :text, null: false
          field :content, :text
          field :author_id, :uuid, references: "users(id)", on_delete: :cascade
          field :published, :boolean, default: false

          enable_rls()

          policy :select, "Published posts are viewable by all" do
            "published = true"
          end
        end
      end
      """
      
      schema_file = Path.join([project_path, "lib", "integration_test", "schema.ex"])
      File.write!(schema_file, schema_content)

      # Step 3: Generate migration from schema
      # In a real test, this would use the actual Mix task
      # For now, we'll simulate the migration generation
      
      # Compile the schema module in the test project context
      old_cwd = File.cwd!()
      File.cd!(project_path)
      
      try do
        # This would normally be done by the Mix task
        Code.compile_file(schema_file)
        
        # Generate SQL content
        sql_content = Tenjin.Generator.Migration.generate_sql_content([IntegrationTest.Schema])
        
        # Create migration file manually (simulating Supabase CLI)
        timestamp = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.to_iso8601() |> String.replace(~r/[^\d]/, "") |> String.slice(0, 14)
        migration_filename = "#{timestamp}_initial_schema.sql"
        migration_path = Path.join([project_path, "supabase", "migrations", migration_filename])
        
        File.write!(migration_path, sql_content)
        
        # Verify migration file was created
        assert File.exists?(migration_path)
        migration_content = File.read!(migration_path)
        
        # Verify migration content
        assert String.contains?(migration_content, "CREATE TABLE users")
        assert String.contains?(migration_content, "CREATE TABLE posts") 
        assert String.contains?(migration_content, "ENABLE ROW LEVEL SECURITY")
        assert String.contains?(migration_content, "CREATE POLICY")
        assert String.contains?(migration_content, "CREATE UNIQUE INDEX")
        
        # Step 4: Validate generated SQL
        assert String.contains?(migration_content, "id uuid")
        assert String.contains?(migration_content, "email text NOT NULL UNIQUE")
        assert String.contains?(migration_content, "author_id uuid REFERENCES users(id) ON DELETE CASCADE")
        
        # Step 5: Test that migration would be applied correctly
        # (In a full integration test, we would start Supabase and apply the migration)
        # For now, we'll just verify the SQL is well-formed
        
        # Check for common SQL issues
        refute String.contains?(migration_content, ";;")  # No double semicolons
        refute String.contains?(migration_content, "CREATE TABLE CREATE TABLE")  # No duplicates
        
        # Check policy syntax
        policy_match = Regex.run(~r/CREATE POLICY .+ ON users/, migration_content)
        assert policy_match, "Should contain a policy creation statement"
        
        # Step 6: Test schema validation
        # The schema module should have compiled without errors
        assert Code.ensure_loaded?(IntegrationTest.Schema)
        
        # Test that schema functions work
        schema = IntegrationTest.Schema.__schema__()
        assert length(schema.tables) == 2
        assert length(schema.tables |> hd() |> Map.get(:policies)) > 0
        
      after
        File.cd!(old_cwd)
      end
    end

    test "schema validation catches errors", %{project_path: project_path} do
      # Test that invalid schema definitions are caught
      invalid_schema_content = """
      defmodule InvalidSchema do
        use Tenjin.Schema

        table "users" do
          field :id, :invalid_type, primary_key: true  # Invalid type
          field :email, :text, unique: true, null: false
        end
      end
      """
      
      schema_file = Path.join([project_path, "lib", "integration_test", "invalid_schema.ex"])
      File.write!(schema_file, invalid_schema_content)

      old_cwd = File.cwd!()
      File.cd!(project_path)
      
      try do
        # This should raise an error due to invalid type
        assert_raise RuntimeError, ~r/Invalid field type/, fn ->
          Code.compile_file(schema_file)
        end
      after
        File.cd!(old_cwd)
      end
    end

    test "empty schema generates minimal migration", %{project_path: project_path} do
      # Test schema with no tables
      empty_schema_content = """
      defmodule EmptySchema do
        use Tenjin.Schema
        
        # No tables defined
      end
      """
      
      schema_file = Path.join([project_path, "lib", "integration_test", "empty_schema.ex"])
      File.write!(schema_file, empty_schema_content)

      old_cwd = File.cwd!()
      File.cd!(project_path)
      
      try do
        Code.compile_file(schema_file)
        
        sql_content = Tenjin.Generator.Migration.generate_sql_content([EmptySchema])
        
        # Should have header but no CREATE statements
        assert String.contains?(sql_content, "-- Tenjin schema migration")
        refute String.contains?(sql_content, "CREATE TABLE")
        refute String.contains?(sql_content, "CREATE POLICY")
        
      after
        File.cd!(old_cwd)
      end
    end
  end

  # Helper functions
  defp supabase_cli_available? do
    case System.cmd("supabase", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp docker_available? do
    case System.cmd("docker", ["info"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
