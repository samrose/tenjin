defmodule Tenjin.Supabase.Config do
  @moduledoc """
  Configuration management for Supabase integration in Tenjin.
  
  This module handles reading and writing Supabase configuration files,
  as well as managing Tenjin-specific settings within Supabase projects.
  """

  @doc """
  Default Supabase configuration template for new projects.
  """
  def default_config do
    """
    # A string used to distinguish different Supabase projects on the same machine.
    # Not used when running Supabase locally.
    project_id = "default"

    [api]
    # Port to use for the API URL.
    port = 54321
    # Schemas to expose in your API. Tables, views and stored procedures in this schema will get API endpoints.
    # public and storage are always included.
    schemas = ["public", "storage", "graphql_public"]
    # Extra schemas to add to the search_path of every request. public is always included.
    extra_search_path = ["public", "extensions"]
    # The maximum number of rows returns from a table or view without either count=exact or count=planned.
    max_rows = 1000

    [db]
    # Port to use for the local database URL.
    port = 54322
    # Enable or disable the Pub/Sub capability for the local database.
    # Pub/Sub is required for the Realtime functionality.
    use_pooler = true
    # Optional settings for the local database.
    # max_connections = 100
    # pool_size = 10
    # pool_size_overflow = 20

    [studio]
    # Port to use for Supabase Studio.
    port = 54323

    [inbucket]
    # Port to use for the email testing server.
    port = 54324

    [storage]
    # The maximum file size allowed (e.g. "5MB", "500KB").
    file_size_limit = "50MiB"

    [auth]
    # The base URL of your website. Used as an allow-list for redirects and for constructing URLs used
    # in emails.
    site_url = "http://localhost:3000"
    # A list of *exact* URLs that auth providers are permitted to redirect to post authentication.
    additional_redirect_urls = ["https://localhost:3000"]
    # How long tokens are valid for, in seconds. Defaults to 3600 (1 hour), maximum 604800 (1 week).
    jwt_expiry = 3600
    # Allow/disallow new user signups to your project.
    enable_signup = true

    [auth.email]
    # Allow/disallow new user signups via email to your project.
    enable_signup = true
    # If enabled, a user will be required to confirm any email change on both the old, and new email addresses. If disabled, only the new email is required to confirm.
    double_confirm_changes = true
    # If enabled, users need to confirm their email address before signing in.
    enable_confirmations = false

    # Use an external OAuth provider. The full list of providers are: `apple`, `azure`, `bitbucket`,
    # `discord`, `facebook`, `github`, `gitlab`, `google`, `keycloak`, `linkedin`, `notion`, `twitch`,
    # `twitter`, `slack`, `spotify`, `workos`, `zoom`.
    [auth.external.apple]
    enabled = false
    client_id = ""
    secret = ""
    # Overrides the default auth redirectUrl.
    redirect_uri = ""
    # Overrides the default auth provider URL. Used to support self-hosted gitlab, single-tenant Azure,
    # or any other third-party OIDC providers.
    url = ""

    [tenjin]
    # Tenjin framework configuration
    enabled = true
    # List of schema modules to process
    schema_modules = []
    # Automatically generate TypeScript types after migrations
    auto_generate_types = true
    # Directory for Tenjin-generated files
    output_dir = "lib"
    """
  end

  @doc """
  Reads the Supabase config.toml file.
  """
  def read_config(project_path) do
    config_file = Path.join([project_path, "supabase", "config.toml"])
    
    case File.read(config_file) do
      {:ok, content} -> 
        case parse_toml(content) do
          {:ok, config} -> {:ok, config}
          {:error, reason} -> {:error, {:parse_error, reason}}
        end
      {:error, :enoent} -> 
        {:error, :config_not_found}
      {:error, reason} -> 
        {:error, reason}
    end
  end

  @doc """
  Writes configuration to the Supabase config.toml file.
  """
  def write_config(project_path, config) do
    config_file = Path.join([project_path, "supabase", "config.toml"])
    
    case to_toml(config) do
      {:ok, content} -> 
        File.write(config_file, content)
      {:error, reason} -> 
        {:error, reason}
    end
  end

  @doc """
  Updates Tenjin-specific configuration in the Supabase config.
  """
  def update_tenjin_config(project_path, tenjin_config) do
    case read_config(project_path) do
      {:ok, config} ->
        updated_config = Map.put(config, "tenjin", tenjin_config)
        write_config(project_path, updated_config)
      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets Tenjin configuration from the Supabase config file.
  """
  def get_tenjin_config(project_path) do
    case read_config(project_path) do
      {:ok, config} ->
        tenjin_config = Map.get(config, "tenjin", %{})
        {:ok, tenjin_config}
      {:error, _} = error ->
        error
    end
  end

  @doc """
  Sets up environment variables for Supabase integration.
  """
  def setup_env_vars(project_info) do
    env_vars = %{
      "SUPABASE_URL" => project_info.status.api,
      "SUPABASE_ANON_KEY" => project_info.status.anon_key,
      "SUPABASE_SERVICE_ROLE_KEY" => project_info.status.service_role_key,
      "DATABASE_URL" => project_info.status.db
    }
    
    # Set environment variables for current process
    Enum.each(env_vars, fn {key, value} ->
      if value do
        System.put_env(key, value)
      end
    end)
    
    {:ok, env_vars}
  end

  @doc """
  Creates a .env.local file with Supabase environment variables.
  """
  def create_env_file(project_path, project_info) do
    env_content = """
    # Supabase Configuration (Generated by Tenjin)
    SUPABASE_URL=#{project_info.status.api}
    SUPABASE_ANON_KEY=#{project_info.status.anon_key}
    SUPABASE_SERVICE_ROLE_KEY=#{project_info.status.service_role_key}
    DATABASE_URL=#{project_info.status.db}
    
    # JWT Secret for local development
    SUPABASE_JWT_SECRET=#{project_info.status.jwt_secret}
    """
    
    env_file = Path.join(project_path, ".env.local")
    File.write(env_file, env_content)
  end

  @doc """
  Validates Supabase configuration.
  """
  def validate_config(config) do
    required_sections = ["api", "db", "studio"]
    errors = []
    
    # Check required sections
    errors = Enum.reduce(required_sections, errors, fn section, acc ->
      if Map.has_key?(config, section) do
        acc
      else
        [{:missing_section, section} | acc]
      end
    end)
    
    # Validate port numbers
    errors = validate_ports(config, errors)
    
    # Validate Tenjin-specific config
    errors = validate_tenjin_config(config, errors)
    
    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  defp validate_ports(config, errors) do
    port_configs = [
      {"api", "port"},
      {"db", "port"},
      {"studio", "port"},
      {"inbucket", "port"}
    ]
    
    Enum.reduce(port_configs, errors, fn {section, port_key}, acc ->
      case get_in(config, [section, port_key]) do
        port when is_integer(port) and port > 0 and port < 65536 -> acc
        port when is_integer(port) -> [{:invalid_port, {section, port}} | acc]
        _ -> [{:missing_port, section} | acc]
      end
    end)
  end

  defp validate_tenjin_config(config, errors) do
    case Map.get(config, "tenjin") do
      nil -> errors
      tenjin_config ->
        # Validate schema_modules is a list
        case Map.get(tenjin_config, "schema_modules") do
          modules when is_list(modules) -> errors
          nil -> errors
          _ -> [{:invalid_schema_modules, "must be a list"} | errors]
        end
    end
  end

  # Simple TOML parsing - in production you might want to use a proper TOML library
  defp parse_toml(content) do
    try do
      config = %{}
      
      # Parse sections and key-value pairs
      lines = String.split(content, "\n")
      {config, _} = parse_toml_lines(lines, config, nil)
      
      {:ok, config}
    rescue
      error -> {:error, error}
    end
  end

  defp parse_toml_lines([], config, _current_section), do: {config, nil}
  
  defp parse_toml_lines([line | rest], config, current_section) do
    trimmed = String.trim(line)
    
    cond do
      # Skip empty lines and comments
      trimmed == "" or String.starts_with?(trimmed, "#") ->
        parse_toml_lines(rest, config, current_section)
      
      # Section headers
      Regex.match?(~r/^\[.+\]$/, trimmed) ->
        section_name = String.slice(trimmed, 1..-2//1)
        new_config = Map.put(config, section_name, %{})
        parse_toml_lines(rest, new_config, section_name)
      
      # Key-value pairs
      String.contains?(trimmed, "=") ->
        [key, value] = String.split(trimmed, "=", parts: 2)
        key = String.trim(key)
        value = parse_toml_value(String.trim(value))
        
        new_config = if current_section do
          put_in(config, [current_section, key], value)
        else
          Map.put(config, key, value)
        end
        
        parse_toml_lines(rest, new_config, current_section)
      
      # Unknown line format
      true ->
        parse_toml_lines(rest, config, current_section)
    end
  end

  defp parse_toml_value(value) do
    cond do
      # String values
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        String.slice(value, 1..-2//1)
      
      # Boolean values
      value == "true" -> true
      value == "false" -> false
      
      # Integer values
      Regex.match?(~r/^\d+$/, value) ->
        String.to_integer(value)
      
      # Float values  
      Regex.match?(~r/^\d+\.\d+$/, value) ->
        String.to_float(value)
      
      # Array values (simplified)
      String.starts_with?(value, "[") and String.ends_with?(value, "]") ->
        value
        |> String.slice(1..-2//1)
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&parse_toml_value/1)
      
      # Default to string
      true -> value
    end
  end

  # Simple TOML generation
  defp to_toml(config) do
    try do
      content = format_toml_config(config)
      {:ok, content}
    rescue
      error -> {:error, error}
    end
  end

  defp format_toml_config(config) do
    # Format top-level keys first
    {top_level, sections} = Map.split_with(config, fn {_k, v} -> not is_map(v) end)
    
    top_level_content = format_toml_section(top_level)
    sections_content = 
      sections
      |> Enum.map(fn {section_name, section_config} ->
        "[#{section_name}]\n" <> format_toml_section(section_config)
      end)
      |> Enum.join("\n")
    
    (top_level_content <> "\n" <> sections_content)
    |> String.trim()
  end

  defp format_toml_section(section) when is_map(section) do
    section
    |> Enum.map(fn {key, value} -> "#{key} = #{format_toml_value(value)}" end)
    |> Enum.join("\n")
  end

  defp format_toml_value(value) when is_binary(value), do: "\"#{value}\""
  defp format_toml_value(value) when is_boolean(value), do: to_string(value)
  defp format_toml_value(value) when is_number(value), do: to_string(value)
  defp format_toml_value(value) when is_list(value) do
    formatted_items = Enum.map(value, &format_toml_value/1)
    "[" <> Enum.join(formatted_items, ", ") <> "]"
  end
  defp format_toml_value(value), do: inspect(value)

  @doc """
  Gets database connection configuration for a given environment.
  """
  def get_db_config(project_path, env \\ :local) do
    case read_config(project_path) do
      {:ok, config} ->
        case env do
          :local ->
            db_config = Map.get(config, "db", %{})
            {:ok, %{
              hostname: "localhost",
              port: Map.get(db_config, "port", 54322),
              database: "postgres",
              username: "postgres",
              password: "postgres"
            }}
          _ ->
            {:error, :unsupported_environment}
        end
      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets API configuration for a given environment.
  """
  def get_api_config(project_path, env \\ :local) do
    case read_config(project_path) do
      {:ok, config} ->
        case env do
          :local ->
            api_config = Map.get(config, "api", %{})
            {:ok, %{
              hostname: "localhost",
              port: Map.get(api_config, "port", 54321),
              schemas: Map.get(api_config, "schemas", ["public"]),
              max_rows: Map.get(api_config, "max_rows", 1000)
            }}
          _ ->
            {:error, :unsupported_environment}
        end
      {:error, _} = error ->
        error
    end
  end
end
