defmodule Tenjin do
  @moduledoc """
  Tenjin is an Elixir framework for building Supabase backend applications using DSL.

  Tenjin provides a declarative DSL for defining database schemas, RLS policies,
  and database functions using Elixir syntax instead of writing SQL directly.
  It generates SQL migrations automatically and integrates with Supabase CLI.

  ## Getting Started

  Create a new Tenjin project:

      mix tenjin.new my_app
      cd my_app

  Define your schema:

      defmodule MyApp.Schema do
        use Tenjin.Schema

        table "users" do
          field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
          field :email, :text, unique: true, null: false
          field :name, :text

          enable_rls()

          policy :select, "Users can view their own profile" do
            "auth.uid() = id"
          end
        end
      end

  Generate and apply migrations:

      mix tenjin.gen.migration
      mix tenjin.migrate

  ## Main Modules

  - `Tenjin.Schema` - Core DSL for defining database schemas
  - `Tenjin.Generator` - SQL generation from schema definitions
  - `Tenjin.Supabase` - Supabase CLI integration
  - `Tenjin.Types` - Type definitions and validations
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the Tenjin version.
  """
  def version, do: @version

  @doc """
  Returns configuration for the current environment.
  """
  def config do
    Application.get_all_env(:tenjin)
  end

  @doc """
  Returns the configured Supabase project directory.
  Defaults to "supabase" if not configured.
  """
  def supabase_dir do
    config()[:supabase_dir] || "supabase"
  end

  @doc """
  Returns the configured migrations directory.
  Defaults to "supabase/migrations" if not configured.
  """
  def migrations_dir do
    Path.join([supabase_dir(), "migrations"])
  end

  @doc """
  Returns the configured schema modules.
  """
  def schema_modules do
    config()[:schema_modules] || []
  end
end
