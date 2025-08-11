defmodule Mix.Tasks.Tenjin.Supabase.Start do
  @shortdoc "Starts the local Supabase development environment"

  @moduledoc """
  Starts the local Supabase development environment.

  This task starts all Supabase services locally using Docker:
  - PostgreSQL database
  - API Gateway
  - Auth service  
  - Realtime service
  - Storage service
  - Dashboard (Studio)

  ## Usage

      mix tenjin.supabase.start [options]

  ## Options

    * `--debug` - Start with debug logging enabled

  ## Examples

      mix tenjin.supabase.start
      mix tenjin.supabase.start --debug

  After starting, you can access:
  - Supabase Studio: http://localhost:54323
  - API: http://localhost:54321
  - Database: postgresql://postgres:postgres@localhost:54322/postgres
  """

  use Mix.Task

  alias Tenjin.Supabase.Project

  @impl Mix.Task  
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: [debug: :boolean])

    project_path = File.cwd!()
    
    # Set debug mode if requested
    debug_mode = opts[:debug] || false
    
    if debug_mode do
      Logger.configure(level: :debug)
      Mix.shell().info("🐛 Debug mode enabled")
      Mix.shell().info("📁 Project path: #{project_path}")
    end
    
    Mix.shell().info("🚀 Starting Supabase development environment...")

    # Validate environment
    if debug_mode, do: Mix.shell().info("🔍 Validating environment...")
    case Project.validate_environment(project_path) do
      :ok -> 
        Mix.shell().info("✅ Environment validation passed")
      {:error, failures} ->
        Mix.shell().error("❌ Environment validation failed:")
        print_validation_failures(failures)
        Mix.raise("Fix the above issues and try again")
    end

    # Start Supabase
    if debug_mode, do: Mix.shell().info("🚀 Calling Supabase start...")
    case Project.start(project_path) do
      {:ok, project_info} ->
        if debug_mode do
          Mix.shell().info("🔍 Supabase started with info: #{inspect(project_info, pretty: true)}")
        end
        print_success_message(project_info)
      {:error, {exit_code, error_output}} when is_integer(exit_code) ->
        Mix.shell().error("❌ Failed to start Supabase (exit code: #{exit_code}):")
        Mix.shell().error(error_output)
        Mix.raise("Supabase startup failed")
      {:error, reason} ->
        Mix.shell().error("❌ Failed to start Supabase: #{inspect(reason)}")
        Mix.raise("Supabase startup failed")
    end
  end

  defp print_validation_failures(failures) do
    Enum.each(failures, fn {check, {:error, reason}} ->
      Mix.shell().error("  • #{check}: #{format_failure_reason(reason)}")
    end)
  end

  defp format_failure_reason(:not_installed), do: "not installed"
  defp format_failure_reason(:not_supabase_project), do: "not a Supabase project (run 'mix tenjin.init')"
  defp format_failure_reason(:docker_not_running), do: "Docker is not running"
  defp format_failure_reason(:docker_not_installed), do: "Docker is not installed"
  defp format_failure_reason({:port_in_use, port}), do: "port #{port} is already in use"
  defp format_failure_reason(reason), do: inspect(reason)

  defp print_success_message(project_info) do
    status = project_info.status

    Mix.shell().info("""

    🎉 Supabase is running!

    Services:
      📊 Studio (Dashboard): #{status.studio}
      🌐 API Gateway:        #{status.api}  
      🗄️  Database:          #{status.db}
      📧 Email (Inbucket):   #{status.inbucket}

    Database Connection:
      Host:     localhost
      Port:     #{extract_port(status.db)}
      Database: postgres
      Username: postgres
      Password: postgres

    Authentication:
      Anon Key:         #{String.slice(status.anon_key || "N/A", 0, 20)}...
      Service Role Key: #{String.slice(status.service_role_key || "N/A", 0, 20)}...
      JWT Secret:       #{String.slice(status.jwt_secret || "N/A", 0, 20)}...

    📝 Next steps:
      1. Visit Studio at #{status.studio} to explore your database
      2. Generate your first migration: mix tenjin.gen.migration initial_schema
      3. Apply migrations: mix tenjin.migrate
      4. Start building your application!

    💡 Tip: Environment variables have been set for this session.
        To persist them, create a .env.local file with these values.
    """)

    # Optionally create .env.local file
    if Mix.shell().yes?("Create .env.local file with environment variables?") do
      case Tenjin.Supabase.Config.create_env_file(File.cwd!(), project_info) do
        :ok ->
          Mix.shell().info("✅ Created .env.local file")
        {:error, reason} ->
          Mix.shell().error("❌ Failed to create .env.local: #{inspect(reason)}")
      end
    end
  end

  defp extract_port(db_url) when is_binary(db_url) do
    case Regex.run(~r/:(\d+)\//, db_url) do
      [_, port] -> port
      _ -> "54322"
    end
  end
  defp extract_port(_), do: "54322"
end
