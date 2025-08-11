defmodule Mix.Tasks.Tenjin.New do
  @shortdoc "Creates a new Tenjin project"

  @moduledoc """
  Creates a new Tenjin project with Supabase integration.

  ## Usage

      mix tenjin.new <project_name> [options]

  ## Options

    * `--path` - specify the path where to create the project
    * `--no-supabase` - skip Supabase initialization
    * `--database-url` - custom database URL

  ## Examples

      mix tenjin.new my_blog
      mix tenjin.new my_api --path /tmp/projects

  """

  use Mix.Task
  import Mix.Generator

  alias Tenjin.Supabase.Project

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, 
      strict: [
        path: :string,
        no_supabase: :boolean,
        database_url: :string
      ]
    ) do
      {opts, [project_name], []} ->
        create_project(project_name, opts)
      {_opts, [], []} ->
        Mix.raise("Expected project name to be given, got: mix tenjin.new")
      {_opts, _args, []} ->
        Mix.raise("Expected a single project name, got multiple arguments")
      {_opts, _args, invalid} ->
        Mix.raise("Invalid options: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")
    end
  end

  defp create_project(project_name, opts) do
    # If path is provided, create project in that directory
    project_path = if opts[:path] do
      Path.join(opts[:path], project_name)
    else
      project_name
    end
    app_name = project_name
    
    Mix.shell().info("Creating Tenjin project #{app_name}...")
    
    # Validate project name
    unless Regex.match?(~r/^[a-z][\w_-]*$/, app_name) do
      Mix.raise("Project name must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens")
    end
    
    # Convert hyphens to underscores for Elixir app name
    elixir_app_name = String.replace(app_name, "-", "_")

    # Create project directory
    File.mkdir_p!(project_path)

    # Generate project structure
    generate_project_structure(project_path, elixir_app_name, opts)

    # Initialize Supabase if requested
    unless opts[:no_supabase] do
      Mix.shell().info("Initializing Supabase project...")
      case Project.init(project_path) do
        {:ok, _} ->
          Mix.shell().info("Supabase initialized successfully")
        {:error, reason} ->
          Mix.shell().error("Failed to initialize Supabase: #{inspect(reason)}")
          Mix.shell().info("You can initialize Supabase later with: cd #{project_path} && mix tenjin.supabase.init")
      end
    end

    # Print success message and instructions
    print_success_message(project_path, app_name, opts)
  end

  defp generate_project_structure(project_path, app_name, opts) do
    # Mix project files
    create_file(Path.join(project_path, "mix.exs"), mix_exs_template(app_name, opts))
    create_file(Path.join(project_path, ".gitignore"), gitignore_template())
    create_file(Path.join(project_path, "README.md"), readme_template(app_name))

    # Configuration files
    config_dir = Path.join(project_path, "config")
    File.mkdir_p!(config_dir)
    create_file(Path.join(config_dir, "config.exs"), config_template())
    create_file(Path.join(config_dir, "dev.exs"), dev_config_template())
    create_file(Path.join(config_dir, "test.exs"), test_config_template())
    create_file(Path.join(config_dir, "runtime.exs"), runtime_config_template())

    # Library structure
    lib_dir = Path.join([project_path, "lib", app_name])
    File.mkdir_p!(lib_dir)
    create_file(Path.join([project_path, "lib", "#{app_name}.ex"]), application_template(app_name))
    create_file(Path.join(lib_dir, "schema.ex"), schema_template(app_name))

    # Test structure
    test_dir = Path.join(project_path, "test")
    File.mkdir_p!(test_dir)
    create_file(Path.join(test_dir, "test_helper.exs"), test_helper_template())
    create_file(Path.join(test_dir, "#{app_name}_test.exs"), test_template(app_name))
    create_file(Path.join([test_dir, app_name, "schema_test.exs"]), schema_test_template(app_name))

    # Seeds directory
    seeds_dir = Path.join([project_path, "priv", "seeds"])
    File.mkdir_p!(seeds_dir)
    create_file(Path.join(seeds_dir, "dev.exs"), seeds_template(app_name))
  end

  # Template functions
  defp mix_exs_template(app_name, _opts) do
    """
    defmodule #{Macro.camelize(app_name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{app_name},
          version: "0.1.0",
          elixir: "~> 1.14",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger],
          mod: {#{Macro.camelize(app_name)}.Application, []}
        ]
      end

      defp deps do
        [
          {:tenjin, path: "#{System.get_env("TENJIN_HOME")}"},
          {:jason, "~> 1.4"},
          {:ex_doc, "~> 0.29", only: :dev, runtime: false}
        ]
      end
    end
    """
  end

  defp gitignore_template do
    """
    # Elixir
    /_build/
    /cover/
    /deps/
    /doc/
    /.fetch
    erl_crash.dump
    *.ez
    *.tar

    # Environment variables
    .env
    .env.local
    .env.*.local

    # Supabase
    .branches
    .temp
    .vercel
    .output
    supabase/.env

    # Editor
    .vscode/
    .idea/
    *.swp
    *.swo
    *~

    # OS
    .DS_Store
    .DS_Store?
    ._*
    .Spotlight-V100
    .Trashes
    ehthumbs.db
    Thumbs.db
    """
  end

  defp readme_template(app_name) do
    """
    # #{Macro.camelize(app_name)}

    A Tenjin-powered application with Supabase backend.

    ## Getting Started

    ### Prerequisites

    - Elixir 1.14+
    - Supabase CLI
    - Docker (for local Supabase)

    ### Setup

    1. Install dependencies:
       ```bash
       mix deps.get
       ```

    2. Start Supabase:
       ```bash
       mix tenjin.supabase.start
       ```

    3. Generate and apply initial migration:
       ```bash
       mix tenjin.gen.migration initial_schema
       mix tenjin.migrate
       ```

    4. Start the application:
       ```bash
       mix tenjin.server
       # or just: iex -S mix
       ```

    ## Schema Definition

    Define your database schema in `lib/#{app_name}/schema.ex`:

    ```elixir
    defmodule #{Macro.camelize(app_name)}.Schema do
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
      end
    end
    ```

    ## Available Commands

    - `mix tenjin.supabase.start` - Start local Supabase
    - `mix tenjin.supabase.stop` - Stop local Supabase
    - `mix tenjin.gen.migration <name>` - Generate migration
    - `mix tenjin.migrate` - Apply migrations
    - `mix tenjin.schema.validate` - Validate schema
    - `mix tenjin.server` - Start development server

    ## Learn More

    - [Tenjin Documentation](https://github.com/tenjin-framework/tenjin)
    - [Supabase Documentation](https://supabase.com/docs)
    """
  end

  defp config_template do
    """
    import Config

    # Import environment specific config
    import_config "\#{config_env()}.exs"
    """
  end

  defp dev_config_template do
    """
    import Config

    # Configure Tenjin
    config :tenjin,
      supabase_dir: "supabase",
      schema_modules: []

    # Development-specific configuration
    config :logger, level: :debug
    """
  end

  defp test_config_template do
    """
    import Config

    # Configure Tenjin for testing
    config :tenjin,
      supabase_dir: "supabase",
      schema_modules: []

    # Test-specific configuration
    config :logger, level: :warn
    """
  end

  defp runtime_config_template do
    """
    import Config

    # Runtime configuration (loads environment variables)
    if config_env() == :prod do
      # Production configuration would go here
    end
    """
  end

  defp application_template(app_name) do
    """
    defmodule #{Macro.camelize(app_name)}.Application do
      @moduledoc false

      use Application

      @impl true
      def start(_type, _args) do
        children = [
          # Start your application processes here
        ]

        opts = [strategy: :one_for_one, name: #{Macro.camelize(app_name)}.Supervisor]
        Supervisor.start_link(children, opts)
      end
    end
    """
  end

  defp schema_template(app_name) do
    """
    defmodule #{Macro.camelize(app_name)}.Schema do
      @moduledoc \"\"\"
      Database schema definition for #{Macro.camelize(app_name)}.
      
      This module defines the database schema using Tenjin's Elixir DSL.
      When you modify this schema, generate a new migration with:
      
          mix tenjin.gen.migration <migration_name>
          
      Then apply the migration with:
      
          mix tenjin.migrate
      \"\"\"
      
      use Tenjin.Schema

      # Example table definition
      # Uncomment and modify as needed:
      
      # table "users" do
      #   field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
      #   field :email, :text, unique: true, null: false
      #   field :name, :text
      #   field :created_at, :timestamptz, default: "now()"
      #   field :updated_at, :timestamptz, default: "now()"
      #   
      #   enable_rls()
      #   
      #   policy :select, "Users can view their own profile" do
      #     "auth.uid() = id"
      #   end
      #   
      #   policy :update, "Users can update their own profile" do
      #     "auth.uid() = id"
      #   end
      #   
      #   index [:email], unique: true
      #   index [:created_at]
      # end
    end
    """
  end

  defp test_helper_template do
    """
    ExUnit.start()
    """
  end

  defp test_template(app_name) do
    """
    defmodule #{Macro.camelize(app_name)}Test do
      use ExUnit.Case
      doctest #{Macro.camelize(app_name)}

      test "application starts" do
        assert {:ok, _} = Application.ensure_all_started(:#{app_name})
      end
    end
    """
  end

  defp schema_test_template(app_name) do
    """
    defmodule #{Macro.camelize(app_name)}.SchemaTest do
      use ExUnit.Case
      
      alias #{Macro.camelize(app_name)}.Schema

      test "schema module loads without errors" do
        # This test ensures the schema compiles correctly
        assert Code.ensure_loaded?(Schema)
      end

      # Add more specific schema tests here
    end
    """
  end

  defp seeds_template(app_name) do
    """
    # #{Macro.camelize(app_name)} Development Seeds
    #
    # This file contains seed data for development.
    # It will be run when you execute: mix tenjin.seed
    #
    # Example:
    # IO.puts "Creating development data..."
    # 
    # # Insert users
    # users_sql = \"\"\"
    # INSERT INTO users (email, name) VALUES 
    #   ('admin@example.com', 'Admin User'),
    #   ('user@example.com', 'Regular User')
    # ON CONFLICT (email) DO NOTHING;
    # \"\"\"
    # 
    # {:ok, _} = Postgrex.query(db_conn, users_sql, [])
    # 
    # IO.puts "Development data created!"

    IO.puts "No seed data defined yet. Add your seeds to priv/seeds/dev.exs"
    """
  end

  defp print_success_message(project_path, app_name, _opts) do
    Mix.shell().info("""

    🎉 Tenjin project #{app_name} created successfully!

    Get started:

        cd #{project_path}
        
    Install dependencies:
        mix deps.get

    Start Supabase (requires Docker):
        mix tenjin.supabase.start

    Generate your first migration:
        mix tenjin.gen.migration initial_schema

    Apply the migration:
        mix tenjin.migrate

    Start an interactive session:
        iex -S mix

    ## Next Steps

    1. Edit lib/#{app_name}/schema.ex to define your database schema
    2. Generate migrations as you update your schema
    3. Use Supabase Studio at http://localhost:54323 to explore your database
    4. Build your application!

    ## Learn More

    * Tenjin Guide: https://github.com/tenjin-framework/tenjin
    * Supabase Docs: https://supabase.com/docs
    """)
  end
end
