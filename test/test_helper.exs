ExUnit.start()

defmodule Tenjin.TestHelpers do
  @moduledoc """
  Test helpers for Tenjin framework tests.
  """

  @doc """
  Creates a temporary directory for testing.
  """
  def tmp_dir do
    System.tmp_dir!()
    |> Path.join("tenjin_test_#{System.unique_integer([:positive])}")
  end

  @doc """
  Creates a temporary project directory with basic structure.
  """
  def create_tmp_project(name \\ "test_project") do
    project_path = tmp_dir()
    File.mkdir_p!(project_path)

    # Create basic mix.exs
    mix_exs_content = """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name},
          version: "0.1.0",
          elixir: "~> 1.14",
          deps: [{:tenjin, path: "#{File.cwd!()}"}]
        ]
      end

      def application do
        [extra_applications: [:logger]]
      end
    end
    """

    File.write!(Path.join(project_path, "mix.exs"), mix_exs_content)

    # Create lib directory and basic schema
    lib_dir = Path.join([project_path, "lib", name])
    File.mkdir_p!(lib_dir)

    schema_content = """
    defmodule #{Macro.camelize(name)}.Schema do
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
    """

    File.write!(Path.join(lib_dir, "schema.ex"), schema_content)

    project_path
  end

  @doc """
  Creates a temporary Supabase project structure.
  """
  def create_supabase_project(project_path) do
    supabase_dir = Path.join(project_path, "supabase")
    File.mkdir_p!(supabase_dir)

    # Create config.toml
    config_content = """
    project_id = "test-project"

    [api]
    port = 54321

    [db]
    port = 54322

    [studio]
    port = 54323

    [tenjin]
    enabled = true
    schema_modules = []
    """

    File.write!(Path.join(supabase_dir, "config.toml"), config_content)

    # Create migrations directory
    migrations_dir = Path.join(supabase_dir, "migrations")
    File.mkdir_p!(migrations_dir)

    supabase_dir
  end

  @doc """
  Cleanup temporary directories.
  """
  def cleanup_tmp_dir(path) do
    if File.exists?(path) do
      File.rm_rf!(path)
    end
  end

  @doc """
  Mock Supabase CLI responses for testing.
  """
  def mock_supabase_cli_response(command, response) do
    # This would be used with a mocking library in real tests
    # For now, just return the expected response format
    case command do
      ["status"] -> {:ok, mock_status_output()}
      ["migration", "new", _name] -> {:ok, mock_migration_output()}
      _ -> {:error, "Command not mocked"}
    end
  end

  defp mock_status_output do
    """
    API URL: http://localhost:54321
    DB URL: postgresql://postgres:postgres@localhost:54322/postgres
    Studio URL: http://localhost:54323
    Inbucket URL: http://localhost:54324
    JWT secret: your-super-secret-jwt-token
    anon key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
    service_role key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
    """
  end

  defp mock_migration_output do
    """
    Created new migration at supabase/migrations/20231201120000_test_migration.sql
    """
  end
end
