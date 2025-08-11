defmodule Mix.Tasks.Tenjin do
  @shortdoc "Prints Tenjin help information"
  
  @moduledoc """
  Prints help information for Tenjin tasks.
  
  ## Usage
  
      mix tenjin
      mix help tenjin
  
  This task provides an overview of all available Tenjin commands.
  """
  
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("""
    Tenjin v#{Application.spec(:tenjin, :vsn)}
    
    Tenjin is an Elixir framework for building Supabase backend applications
    using Elixir DSL instead of writing SQL directly.
    
    ## Available Commands
    
    ### Project Management
      mix tenjin.new <project_name>  # Create new Tenjin project
      mix tenjin.init                # Initialize Tenjin in existing project
    
    ### Supabase Integration  
      mix tenjin.supabase.start      # Start local Supabase
      mix tenjin.supabase.stop       # Stop local Supabase  
      mix tenjin.supabase.status     # Check Supabase status
      mix tenjin.supabase.reset      # Reset local database
    
    ### Schema & Migration Management
      mix tenjin.gen.migration <name> # Generate migration from schema
      mix tenjin.migrate              # Apply pending migrations
      mix tenjin.rollback             # Rollback last migration
      mix tenjin.schema.dump          # Dump current schema to SQL
      mix tenjin.schema.validate      # Validate schema definitions
    
    ### Development
      mix tenjin.server              # Start development server  
      mix tenjin.console             # Interactive console
      mix tenjin.seed                # Run seed files
    
    ### Code Generation
      mix tenjin.gen.table <name>    # Generate table boilerplate
      mix tenjin.gen.function <name> # Generate function boilerplate
      mix tenjin.gen.policy <table>  # Generate RLS policy boilerplate
    
    ### SQL Generation & Testing
      mix tenjin.sql.generate        # Generate SQL from current schema
      mix tenjin.db.status          # Check database connection status
    
    ## Examples
    
      # Create new project
      mix tenjin.new my_blog
      cd my_blog
      
      # Start Supabase
      mix tenjin.supabase.start
      
      # Generate migration from schema  
      mix tenjin.gen.migration initial_schema
      
      # Apply migrations
      mix tenjin.migrate
      
      # Start development server
      mix tenjin.server
    
    ## Getting Help
    
    For detailed help on any command, use:
      mix help tenjin.<command>
      
    For more information, visit: https://github.com/tenjin-framework/tenjin
    """)
  end
end
