defmodule Tenjin.Supabase.CLI do
  @moduledoc """
  Wrapper for Supabase CLI commands.
  
  This module provides functions to execute Supabase CLI commands
  and parse their output.
  """

  require Logger

  @doc """
  Executes a Supabase CLI command.
  
  ## Options
  
    * `:cd` - Change to directory before running command
    * `:env` - Environment variables
    * `:timeout` - Command timeout in milliseconds (default: 30_000)
    * `:capture_output` - Whether to capture output (default: true)
  
  ## Examples
  
      CLI.run_command(["status"])
      CLI.run_command(["db", "push"], cd: "/path/to/project")
  """
  def run_command(args, opts \\ []) do
    env = opts[:env] || []
    cd = opts[:cd] || File.cwd!()
    capture_output = Keyword.get(opts, :capture_output, true)
    timeout = Keyword.get(opts, :timeout, 30_000)

    cmd_args = ["supabase"] ++ args
    
    Logger.debug("Running Supabase command: #{Enum.join(cmd_args, " ")}")
    Logger.debug("Working directory: #{cd}")
    Logger.debug("Timeout: #{timeout}ms")

    # Use shell command approach to avoid System.cmd issues
    cmd_string = "cd #{cd} && supabase " <> Enum.join(args, " ")
    Logger.debug("Shell command: #{cmd_string}")
    
    try do
      # Wrap in Task to handle timeout
      task = Task.async(fn ->
        if capture_output do
          case System.cmd("sh", ["-c", cmd_string], [env: env, stderr_to_stdout: true]) do
            {output, 0} -> {:ok, output}
            {error, exit_code} -> {:error, {exit_code, error}}
          end
        else
          case System.cmd("sh", ["-c", cmd_string], [env: env, into: IO.stream()]) do
            {_, 0} -> {:ok, ""}
            {_, exit_code} -> {:error, {exit_code, ""}}
          end
        end
      end)
      
      Task.await(task, timeout)
    rescue
      error in ErlangError ->
        case error.original do
          :enoent -> {:error, :supabase_not_found}
          _ -> {:error, error}
        end
      
      error ->
        {:error, error}
    catch
      :exit, {:timeout, _} -> {:error, :command_timeout}
    end
  end

  @doc """
  Checks if Supabase CLI is installed and accessible.
  """
  def check_installation do
    case run_command(["--version"]) do
      {:ok, version_output} -> 
        version = String.trim(version_output)
        {:ok, version}
      {:error, :supabase_not_found} -> 
        {:error, :not_installed}
      {:error, _} -> 
        {:error, :not_accessible}
    end
  end

  @doc """
  Initializes a new Supabase project.
  """
  def init_project(project_name, opts \\ []) do
    args = ["init", project_name]
    
    args = if opts[:with_vscode_settings] do
      args ++ ["--with-vscode-settings"]
    else
      args
    end

    run_command(args, opts)
  end

  @doc """
  Starts the local Supabase development environment.
  """
  def start_project(opts \\ []) do
    args = ["start"]
    
    # Add debug flag if requested
    args = if opts[:debug], do: args ++ ["--debug"], else: args
    
    run_command(args, Keyword.put(opts, :timeout, 120_000)) # 2 minute timeout for start
  end

  @doc """
  Stops the local Supabase development environment.
  """
  def stop_project(opts \\ []) do
    run_command(["stop"], opts)
  end

  @doc """
  Gets the status of the local Supabase environment.
  """
  def status(opts \\ []) do
    case run_command(["status"], opts) do
      {:ok, output} -> parse_status_output(output)
      {:error, _} = error -> error
    end
  end

  @doc """
  Resets the local database.
  """
  def reset_db(opts \\ []) do
    run_command(["db", "reset"], Keyword.put(opts, :timeout, 60_000)) # 1 minute timeout
  end

  @doc """
  Pushes database changes (applies migrations).
  """
  def db_push(opts \\ []) do
    args = ["db", "push"]
    
    args = if opts[:local], do: args ++ ["--local"], else: args
    args = if opts[:dry_run], do: args ++ ["--dry-run"], else: args
    args = if opts[:include_seed], do: args ++ ["--include-seed"], else: args
    
    run_command(args, opts)
  end

  @doc """
  Creates a new database migration.
  """
  def db_new_migration(name, opts \\ []) do
    args = ["migration", "new", name]
    # Use the same timeout as start_project which works
    run_command(args, Keyword.put(opts, :timeout, 120_000)) # 2 minute timeout like start command
  end

  @doc """
  Creates a diff migration by comparing current schema with database.
  """
  def db_diff(migration_name, opts \\ []) do
    args = ["db", "diff", "--name", migration_name]
    
    args = if opts[:schema], do: args ++ ["--schema", opts[:schema]], else: args
    args = if opts[:exclude_schema], do: args ++ ["--exclude-schema", opts[:exclude_schema]], else: args
    
    run_command(args, opts)
  end

  @doc """
  Generates TypeScript types from database schema.
  """
  def gen_types(opts \\ []) do
    args = ["gen", "types", "typescript"]
    
    args = case opts[:output_file] do
      nil -> args ++ ["--local"]
      file -> args ++ ["--local"] ++ ["--output", file]
    end
    
    run_command(args, opts)
  end

  @doc """
  Links project to a remote Supabase project.
  """
  def link_project(project_ref, opts \\ []) do
    args = ["link", "--project-ref", project_ref]
    
    args = case opts[:password] do
      nil -> args
      password -> args ++ ["--password", password]
    end
    
    run_command(args, opts)
  end

  @doc """
  Deploys database changes to remote project.
  """
  def db_deploy(opts \\ []) do
    args = ["db", "deploy"]
    
    args = if opts[:dry_run], do: args ++ ["--dry-run"], else: args
    args = if opts[:create_backup], do: args ++ ["--create-backup"], else: args
    
    run_command(args, opts)
  end

  @doc """
  Lists available storage buckets.
  """
  def storage_list(opts \\ []) do
    case run_command(["storage", "ls"], opts) do
      {:ok, output} -> parse_storage_list_output(output)
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a storage bucket.
  """
  def storage_create_bucket(bucket_name, opts \\ []) do
    args = ["storage", "create", bucket_name]
    
    args = if opts[:public], do: args ++ ["--public"], else: args
    
    run_command(args, opts)
  end

  @doc """
  Runs Supabase Edge Functions locally.
  """
  def functions_serve(opts \\ []) do
    args = ["functions", "serve"]
    
    args = case opts[:port] do
      nil -> args
      port -> args ++ ["--port", to_string(port)]
    end
    
    args = if opts[:debug], do: args ++ ["--debug"], else: args
    
    run_command(args, Keyword.put(opts, :capture_output, false))
  end

  @doc """
  Creates a new Edge Function.
  """
  def functions_new(function_name, opts \\ []) do
    args = ["functions", "new", function_name]
    run_command(args, opts)
  end

  @doc """
  Deploys Edge Functions.
  """
  def functions_deploy(opts \\ []) do
    args = ["functions", "deploy"]
    
    args = case opts[:function_name] do
      nil -> args
      name -> args ++ [name]
    end
    
    args = if opts[:no_verify_jwt], do: args ++ ["--no-verify-jwt"], else: args
    
    run_command(args, opts)
  end

  # Private helper functions

  defp parse_status_output(output) do
    lines = String.split(output, "\n")
    
    status = %{
      api: parse_service_status(lines, "API URL"),
      db: parse_service_status(lines, "DB URL"),
      studio: parse_service_status(lines, "Studio URL"),
      inbucket: parse_service_status(lines, "Inbucket URL"),
      jwt_secret: parse_config_value(lines, "JWT secret"),
      anon_key: parse_config_value(lines, "anon key"),
      service_role_key: parse_config_value(lines, "service_role key"),
      running: true
    }
    
    {:ok, status}
  rescue
    _ -> {:error, "Failed to parse status output"}
  end

  defp parse_service_status(lines, service_name) do
    line = Enum.find(lines, &String.contains?(&1, service_name))
    
    if line do
      case Regex.run(~r/#{service_name}:\s*(.+)/, line) do
        [_, url] -> String.trim(url)
        _ -> nil
      end
    else
      nil
    end
  end

  defp parse_config_value(lines, config_name) do
    line = Enum.find(lines, &String.contains?(&1, config_name))
    
    if line do
      case Regex.run(~r/#{config_name}:\s*(.+)/, line) do
        [_, value] -> String.trim(value)
        _ -> nil
      end
    else
      nil
    end
  end

  defp parse_storage_list_output(output) do
    lines = 
      output
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.drop(1) # Skip header

    buckets = Enum.map(lines, fn line ->
      [name, public, created_at] = String.split(line, "|") |> Enum.map(&String.trim/1)
      %{
        name: name,
        public: public == "true",
        created_at: created_at
      }
    end)

    {:ok, buckets}
  rescue
    _ -> {:error, "Failed to parse storage list output"}
  end

  @doc """
  Gets the project configuration.
  """
  def get_project_config(opts \\ []) do
    cd = opts[:cd] || File.cwd!()
    config_file = Path.join(cd, "supabase/config.toml")
    
    if File.exists?(config_file) do
      case File.read(config_file) do
        {:ok, content} -> parse_config_toml(content)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :config_not_found}
    end
  end

  defp parse_config_toml(content) do
    # This is a simple TOML parser - in production you might want to use a proper TOML library
    config = %{}
    
    # Extract project_id
    project_id = case Regex.run(~r/project_id\s*=\s*"([^"]+)"/, content) do
      [_, id] -> id
      _ -> nil
    end
    
    # Extract database configuration
    db_config = %{}
    db_config = case Regex.run(~r/port\s*=\s*(\d+)/, content) do
      [_, port] -> Map.put(db_config, :port, String.to_integer(port))
      _ -> db_config
    end
    
    config = Map.put(config, :project_id, project_id)
    config = Map.put(config, :db, db_config)
    
    {:ok, config}
  rescue
    _ -> {:error, "Failed to parse config.toml"}
  end

  @doc """
  Checks if we're in a Supabase project directory.
  """
  def in_project?(opts \\ []) do
    cd = opts[:cd] || File.cwd!()
    config_file = Path.join(cd, "supabase/config.toml")
    File.exists?(config_file)
  end

  @doc """
  Gets database connection URL from local environment.
  """
  def get_db_url(opts \\ []) do
    case status(opts) do
      {:ok, %{db: db_url}} when is_binary(db_url) -> {:ok, db_url}
      {:ok, _} -> {:error, :db_not_running}
      {:error, _} = error -> error
    end
  end
end
