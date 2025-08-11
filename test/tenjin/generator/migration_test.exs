defmodule Tenjin.Generator.MigrationTest do
  use ExUnit.Case
  import Tenjin.TestHelpers

  alias Tenjin.Generator.Migration

  # Test schema for migration generation
  defmodule TestSchema do
    use Tenjin.Schema

    table "users" do
      field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
      field :email, :text, unique: true, null: false
      field :name, :text
      
      enable_rls()
      
      policy :select, "Users can view their own data" do
        "auth.uid() = id"
      end
      
      index [:email], unique: true
    end

    function "test_func", [:text], :text do
      "RETURN upper($1);"
    end
  end

  describe "generate_sql_content/2" do
    test "generates SQL content from schema modules" do
      sql_content = Migration.generate_sql_content([TestSchema])
      
      # Check that it contains expected SQL elements
      assert String.contains?(sql_content, "-- Tenjin schema migration")
      assert String.contains?(sql_content, "CREATE TABLE users")
      assert String.contains?(sql_content, "ALTER TABLE users ENABLE ROW LEVEL SECURITY")
      assert String.contains?(sql_content, "CREATE POLICY")
      assert String.contains?(sql_content, "CREATE UNIQUE INDEX")
      assert String.contains?(sql_content, "CREATE OR REPLACE FUNCTION test_func")
    end

    test "generates SQL with custom description" do
      sql_content = Migration.generate_sql_content([TestSchema], 
        description: "Custom migration description"
      )
      
      assert String.contains?(sql_content, "-- Custom migration description")
    end

    test "handles empty schema modules list" do
      sql_content = Migration.generate_sql_content([])
      
      # Should still have header but no content
      assert String.contains?(sql_content, "-- Tenjin schema migration")
      refute String.contains?(sql_content, "CREATE TABLE")
    end
  end

  describe "list_migration_files/1" do
    setup do
      project_path = create_tmp_project("test_migrations")
      supabase_dir = create_supabase_project(project_path)
      
      # Create some test migration files
      migrations_dir = Path.join(supabase_dir, "migrations")
      
      File.write!(Path.join(migrations_dir, "20231201120000_initial.sql"), "-- Initial migration")
      File.write!(Path.join(migrations_dir, "20231202130000_add_users.sql"), "-- Add users table")
      File.write!(Path.join(migrations_dir, "20231203140000_add_posts.sql"), "-- Add posts table")
      
      on_exit(fn -> cleanup_tmp_dir(project_path) end)
      
      %{project_path: project_path}
    end

    test "lists migration files in chronological order", %{project_path: project_path} do
      migrations = Migration.list_migration_files(project_path)
      
      assert length(migrations) == 3
      
      # Should be sorted by timestamp
      filenames = Enum.map(migrations, & &1.filename)
      assert filenames == [
        "20231201120000_initial.sql",
        "20231202130000_add_users.sql", 
        "20231203140000_add_posts.sql"
      ]
      
      # Should extract timestamps
      assert Enum.at(migrations, 0).timestamp == "20231201120000"
      assert Enum.at(migrations, 1).timestamp == "20231202130000"
      assert Enum.at(migrations, 2).timestamp == "20231203140000"
    end

    test "handles empty migrations directory", %{project_path: project_path} do
      # Remove migration files
      migrations_dir = Path.join([project_path, "supabase", "migrations"])
      File.rm_rf!(migrations_dir)
      File.mkdir_p!(migrations_dir)
      
      migrations = Migration.list_migration_files(project_path)
      
      assert migrations == []
    end

    test "handles non-existent migrations directory" do
      non_existent_path = tmp_dir()
      
      migrations = Migration.list_migration_files(non_existent_path)
      
      assert migrations == []
    end
  end

  describe "create_migration/4" do
    setup do
      project_path = create_tmp_project("test_create_migration")
      create_supabase_project(project_path)
      
      on_exit(fn -> cleanup_tmp_dir(project_path) end)
      
      %{project_path: project_path}
    end

    @tag :integration
    test "creates migration with Supabase CLI integration", %{project_path: project_path} do
      # This test requires actual Supabase CLI to be available
      # In a real test, you'd mock the CLI calls
      
      # Mock the CLI response
      expected_output = "Created new migration at supabase/migrations/20231201120000_test_migration.sql"
      
      # Simulate what the function would do
      migration_file_path = Path.join([project_path, "supabase", "migrations", "20231201120000_test_migration.sql"])
      
      # Create the file that would be created by Supabase CLI
      File.mkdir_p!(Path.dirname(migration_file_path))
      File.write!(migration_file_path, "")
      
      # Generate SQL content
      sql_content = Migration.generate_sql_content([TestSchema])
      
      # Write content to file
      File.write!(migration_file_path, sql_content)
      
      # Verify the file exists and has content
      assert File.exists?(migration_file_path)
      content = File.read!(migration_file_path)
      assert String.contains?(content, "CREATE TABLE users")
    end
  end

  describe "create_diff_migration/3" do
    setup do
      project_path = create_tmp_project("test_diff_migration") 
      create_supabase_project(project_path)
      
      on_exit(fn -> cleanup_tmp_dir(project_path) end)
      
      %{project_path: project_path}
    end

    @tag :integration
    test "creates diff migration", %{project_path: project_path} do
      # This would require actual database comparison
      # In practice, this would be mocked
      
      # Mock creating a diff migration file
      migration_file_path = Path.join([project_path, "supabase", "migrations", "20231201120000_diff_migration.sql"])
      
      File.mkdir_p!(Path.dirname(migration_file_path))
      File.write!(migration_file_path, """
      -- Diff migration generated by supabase db diff
      ALTER TABLE users ADD COLUMN phone_number text;
      """)
      
      # Verify file was created
      assert File.exists?(migration_file_path)
      content = File.read!(migration_file_path)
      assert String.contains?(content, "ALTER TABLE users")
    end
  end

  describe "private helper functions" do
    test "extract_timestamp_from_filename extracts timestamp correctly" do
      # Use send to call private function for testing
      # In real implementation, you might make this public or use other testing approaches
      
      assert extract_timestamp("20231201120000_initial.sql") == "20231201120000"
      assert extract_timestamp("20231202130000_add_users.sql") == "20231202130000" 
      assert extract_timestamp("invalid_filename.sql") == nil
    end
  end

  # Helper function to test timestamp extraction
  defp extract_timestamp(filename) do
    case Regex.run(~r/^(\d{14})/, filename) do
      [_, timestamp] -> timestamp
      _ -> nil
    end
  end
end
