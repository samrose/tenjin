defmodule Tenjin.Supabase.Project do
  @moduledoc """
  Supabase project management utilities.
  
  This module handles creating, configuring, and managing Supabase projects
  within the Tenjin framework.
  """

  alias Tenjin.Supabase.CLI
  require Logger

  @doc """
  Initializes a new Supabase project within a Tenjin project.
  """
  def init(project_path) do
    Logger.info("Initializing Supabase project at #{project_path}")
    
    with :ok <- ensure_directory_exists(project_path),
         {:ok, _} <- CLI.init_project(".", cd: project_path),
         :ok <- create_seed_files(project_path),
         :ok <- update_gitignore(project_path) do
      
      Logger.info("Supabase project initialized successfully")
      {:ok, project_path}
    else
      {:error, reason} -> 
        Logger.error("Failed to initialize Supabase project: #{inspect(reason)}")
        {:error, reason}
    end
  end


  @doc """
  Creates seed files directory and initial seed files.
  """
  def create_seed_files(project_path) do
    seeds_dir = Path.join([project_path, "supabase", "seeds"])
    File.mkdir_p!(seeds_dir)
    
    # Create a sample seed file
    seed_content = """
    -- Tenjin Seed File
    -- This file is run after migrations to populate initial data

    -- Example: Insert default admin user
    -- INSERT INTO users (id, email, role) VALUES 
    --   (gen_random_uuid(), 'admin@example.com', 'admin')
    -- ON CONFLICT (email) DO NOTHING;
    """
    
    seed_file = Path.join(seeds_dir, "01_initial_data.sql")
    File.write!(seed_file, seed_content)
    
    :ok
  end

  @doc """
  Updates the project .gitignore to include Supabase-specific entries.
  """
  def update_gitignore(project_path) do
    gitignore_path = Path.join(project_path, ".gitignore")
    
    supabase_entries = """

    # Supabase
    .branches
    .temp
    .env.local
    .env.*.local
    supabase/.env
    supabase/.env.local
    """
    
    case File.read(gitignore_path) do
      {:ok, content} ->
        if String.contains?(content, "# Supabase") do
          :ok  # Already has Supabase entries
        else
          File.write(gitignore_path, content <> supabase_entries)
        end
        
      {:error, :enoent} ->
        # Create new .gitignore
        File.write!(gitignore_path, supabase_entries)
        :ok
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Starts the Supabase development environment.
  """
  def start(project_path) do
    Logger.info("Starting Supabase development environment")
    
    case CLI.start_project(cd: project_path) do
      {:ok, _output} ->
        Logger.info("Supabase started successfully")
        get_project_info(project_path)
        
      {:error, reason} ->
        Logger.error("Failed to start Supabase: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops the Supabase development environment.
  """
  def stop(project_path) do
    Logger.info("Stopping Supabase development environment")
    
    case CLI.stop_project(cd: project_path) do
      {:ok, _output} ->
        Logger.info("Supabase stopped successfully")
        :ok
        
      {:error, reason} ->
        Logger.error("Failed to stop Supabase: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets the current project status and information.
  """
  def get_project_info(project_path) do
    with {:ok, status} <- CLI.status(cd: project_path),
         {:ok, config} <- CLI.get_project_config(cd: project_path) do
      
      project_info = %{
        status: status,
        config: config,
        path: project_path,
        running: status.running
      }
      
      {:ok, project_info}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Resets the local database to a clean state.
  """
  def reset_database(project_path) do
    Logger.info("Resetting database")
    
    case CLI.reset_db(cd: project_path) do
      {:ok, _output} ->
        Logger.info("Database reset successfully")
        :ok
        
      {:error, reason} ->
        Logger.error("Failed to reset database: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Applies pending migrations to the database.
  """
  def migrate(project_path, opts \\ []) do
    Logger.info("Applying database migrations")
    
    cli_opts = [cd: project_path]
    cli_opts = if opts[:dry_run], do: Keyword.put(cli_opts, :dry_run, true), else: cli_opts
    cli_opts = if opts[:include_seed], do: Keyword.put(cli_opts, :include_seed, true), else: cli_opts
    
    case CLI.db_push(cli_opts) do
      {:ok, output} ->
        Logger.info("Migrations applied successfully")
        {:ok, output}
        
      {:error, reason} ->
        Logger.error("Failed to apply migrations: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generates TypeScript types from the current database schema.
  """
  def generate_types(project_path, opts \\ []) do
    Logger.info("Generating TypeScript types")
    
    cli_opts = [cd: project_path]
    cli_opts = if opts[:output_file] do
      Keyword.put(cli_opts, :output_file, opts[:output_file])
    else
      cli_opts
    end
    
    case CLI.gen_types(cli_opts) do
      {:ok, output} ->
        Logger.info("Types generated successfully")
        {:ok, output}
        
      {:error, reason} ->
        Logger.error("Failed to generate types: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Creates a new migration file using Supabase CLI.
  """
  def new_migration(project_path, migration_name) do
    Logger.info("Creating new migration: #{migration_name}")
    
    case CLI.db_new_migration(migration_name, cd: project_path) do
      {:ok, output} ->
        # Parse output to get migration file path
        case extract_migration_path(output) do
          {:ok, migration_path} ->
            Logger.info("Migration created: #{migration_path}")
            {:ok, migration_path}
          :error ->
            Logger.info("Migration created successfully")
            {:ok, output}
        end
        
      {:error, reason} ->
        Logger.error("Failed to create migration: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_migration_path(output) do
    case Regex.run(~r/Created new migration at (.+\.sql)/, output) do
      [_, path] -> {:ok, String.trim(path)}
      _ -> :error
    end
  end

  @doc """
  Links the local project to a remote Supabase project.
  """
  def link_remote(project_path, project_ref, opts \\ []) do
    Logger.info("Linking to remote project: #{project_ref}")
    
    cli_opts = [cd: project_path]
    cli_opts = if opts[:password] do
      Keyword.put(cli_opts, :password, opts[:password])
    else
      cli_opts
    end
    
    case CLI.link_project(project_ref, cli_opts) do
      {:ok, output} ->
        Logger.info("Project linked successfully")
        {:ok, output}
        
      {:error, reason} ->
        Logger.error("Failed to link project: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deploys database changes to the remote project.
  """
  def deploy(project_path, opts \\ []) do
    Logger.info("Deploying database changes")
    
    cli_opts = [cd: project_path]
    cli_opts = if opts[:dry_run], do: Keyword.put(cli_opts, :dry_run, true), else: cli_opts
    cli_opts = if opts[:create_backup], do: Keyword.put(cli_opts, :create_backup, true), else: cli_opts
    
    case CLI.db_deploy(cli_opts) do
      {:ok, output} ->
        Logger.info("Database deployed successfully")
        {:ok, output}
        
      {:error, reason} ->
        Logger.error("Failed to deploy database: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Creates storage buckets defined in the schema.
  """
  def create_storage_buckets(project_path, bucket_configs) when is_list(bucket_configs) do
    Logger.info("Creating storage buckets")
    
    results = Enum.map(bucket_configs, fn %{name: name, options: opts} ->
      cli_opts = [cd: project_path]
      cli_opts = if opts[:public], do: Keyword.put(cli_opts, :public, true), else: cli_opts
      
      case CLI.storage_create_bucket(name, cli_opts) do
        {:ok, _} -> {:ok, name}
        {:error, reason} -> {:error, {name, reason}}
      end
    end)
    
    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))
    
    if Enum.empty?(failures) do
      Logger.info("All storage buckets created successfully")
      {:ok, Enum.map(successes, fn {:ok, name} -> name end)}
    else
      Logger.error("Some storage buckets failed to create: #{inspect(failures)}")
      {:error, failures}
    end
  end

  @doc """
  Validates that the project environment is properly set up.
  """
  def validate_environment(project_path) do
    validations = [
      {"Supabase CLI installed", &validate_supabase_cli/0},
      {"Supabase project exists", fn -> validate_supabase_project(project_path) end},
      {"Docker running", &validate_docker/0},
      {"Required ports available", fn -> validate_ports(project_path) end}
    ]
    
    results = Enum.map(validations, fn {name, validation_fn} ->
      case validation_fn.() do
        :ok -> {name, :ok}
        {:error, reason} -> {name, {:error, reason}}
      end
    end)
    
    failures = Enum.filter(results, fn {_, result} -> match?({:error, _}, result) end)
    
    if Enum.empty?(failures) do
      :ok
    else
      {:error, failures}
    end
  end

  defp validate_supabase_cli do
    case CLI.check_installation() do
      {:ok, _version} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_supabase_project(project_path) do
    if CLI.in_project?(cd: project_path) do
      :ok
    else
      {:error, :not_supabase_project}
    end
  end

  defp validate_docker do
    case System.cmd("docker", ["info"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, _} -> {:error, :docker_not_running}
    end
  rescue
    ErlangError -> {:error, :docker_not_installed}
  end

  defp validate_ports(project_path) do
    # This is a simplified port check - in practice you'd check all Supabase ports
    case CLI.get_project_config(cd: project_path) do
      {:ok, %{db: %{port: port}}} ->
        if port_available?(port) do
          :ok
        else
          {:error, {:port_in_use, port}}
        end
      _ ->
        :ok  # Can't determine port, assume it's fine
    end
  end

  defp port_available?(port) do
    case :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true
      {:error, :eaddrinuse} ->
        false
      {:error, _} ->
        true  # Other errors, assume port is available
    end
  end

  defp ensure_directory_exists(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
