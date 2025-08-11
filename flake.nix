{
  description = "Tenjin - Supabase Elixir Framework Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Elixir version
        elixir = pkgs.beam.packages.erlang_27.elixir_1_17;
        
        # Supabase CLI
        supabase-cli = pkgs.supabase-cli;
        
        # Tenjin CLI wrapper script
        tenjin-cli = pkgs.writeShellScriptBin "tenjin" ''
          #!/usr/bin/env bash
          
          # Tenjin CLI - Wrapper around Mix tasks for Tenjin framework
          # This provides a more user-friendly interface to Tenjin functionality
          
          set -euo pipefail
          
          # Default values
          COMMAND=""
          VERBOSE=false
          DRY_RUN=false
          
          # Colors for output
          RED='\033[0;31m'
          GREEN='\033[0;32m'
          YELLOW='\033[1;33m'
          BLUE='\033[0;34m'
          NC='\033[0m' # No Color
          
          # Set up environment
          export MIX_ENV=''${MIX_ENV:-dev}
          export PATH="${elixir}/bin:${supabase-cli}/bin:$PATH"
          
          # Print colored output
          print_info() {
              echo -e "''${BLUE}ℹ️  $1''${NC}"
          }
          
          print_success() {
              echo -e "''${GREEN}✅ $1''${NC}"
          }
          
          print_warning() {
              echo -e "''${YELLOW}⚠️  $1''${NC}"
          }
          
          print_error() {
              echo -e "''${RED}❌ $1''${NC}"
          }
          
          # Show help
          show_help() {
              cat << 'EOF'
          Tenjin CLI - Supabase + Elixir Framework
          
          Usage: tenjin <command> [options]
          
          COMMANDS:
          
            Project Management:
              new <name>           Create a new Tenjin project
              init                 Initialize Tenjin in existing project
          
            Supabase Management:
              start               Start local Supabase environment
              stop                Stop local Supabase environment  
              status              Show Supabase status
              reset               Reset local database
          
            Schema & Migrations:
              generate <name>     Generate migration from schema
              migrate             Apply pending migrations
              rollback            Rollback last migration
              sql                 Generate SQL from current schema
          
            Development:
              server              Start development server
              console             Start interactive console
              seed                Run database seeds
          
            Utilities:
              validate            Validate schema definitions
              version             Show Tenjin version
              help                Show this help message
          
          GLOBAL OPTIONS:
              -v, --verbose       Verbose output
              -d, --dry-run      Show what would be done (where applicable)
              -h, --help         Show help for command
          
          EXAMPLES:
              tenjin new my_blog                    # Create new project
              tenjin start                          # Start Supabase
              tenjin generate create_users_table    # Generate migration
              tenjin migrate                        # Apply migrations
              tenjin sql --output schema.sql        # Export schema to SQL
          
          For detailed help on a specific command:
              tenjin <command> --help
          
          EOF
          }
          
          # Parse global options
          parse_global_opts() {
              while [[ $# -gt 0 ]]; do
                  case $1 in
                      -v|--verbose)
                          VERBOSE=true
                          shift
                          ;;
                      -d|--dry-run)
                          DRY_RUN=true
                          shift
                          ;;
                      -h|--help)
                          show_help
                          exit 0
                          ;;
                      --)
                          shift
                          break
                          ;;
                      -*)
                          print_error "Unknown global option: $1"
                          print_info "Use 'tenjin --help' for usage information"
                          exit 1
                          ;;
                      *)
                          COMMAND=$1
                          shift
                          break
                          ;;
                  esac
              done
          }
          
          # Check if we're in a valid environment
          check_environment() {
              # Check if we have mix available
              if ! command -v mix &> /dev/null; then
                  print_error "Elixir/Mix not found. Please install Elixir."
                  print_info "Visit: https://elixir-lang.org/install.html"
                  exit 1
              fi
          
              # For commands that need Supabase CLI
              case "$COMMAND" in
                  start|stop|status|reset|migrate|generate)
                      if ! command -v supabase &> /dev/null; then
                          print_error "Supabase CLI not found. Please install Supabase CLI."
                          print_info "Visit: https://supabase.com/docs/guides/cli"
                          exit 1
                      fi
                      ;;
              esac
          }
          
          # Execute Mix task with proper options
          run_mix_task() {
              local task=$1
              shift
              local args=("$@")
          
              # Add global options to mix command
              local mix_args=()
              
              if [ "$VERBOSE" = true ]; then
                  mix_args+=(--verbose)
              fi
          
              if [ "$DRY_RUN" = true ]; then
                  mix_args+=(--dry-run)
              fi
          
              # For new command, run from Tenjin framework directory but create project in current dir
              if [ "$task" = "tenjin.new" ]; then
                  if [ -z "''${TENJIN_HOME:-}" ]; then
                      print_error "TENJIN_HOME not set. Please run from within 'nix develop' shell"
                      exit 1
                  fi
                  
                  local current_dir="$PWD"
                  cd "$TENJIN_HOME"
                  
                  # Check if dependencies are available, fetch if needed
                  if [ ! -d "deps" ] || [ ! -f "_build/dev/lib/*/ebin" ]; then
                      print_info "Fetching Tenjin framework dependencies..."
                      mix deps.get
                      if [ $? -ne 0 ]; then
                          print_error "Failed to fetch dependencies"
                          exit 1
                      fi
                  fi
                  
                  if [ "$VERBOSE" = true ]; then
                      print_info "Executing: mix $task --path $current_dir ''${mix_args[*]} ''${args[*]}"
                  fi
                  exec mix "$task" --path "$current_dir" "''${mix_args[@]}" "''${args[@]}"
              else
                  # For other commands, ensure we're in a project directory
                  if [ ! -f "mix.exs" ]; then
                      print_error "Not in a Mix project directory"
                      print_info "Run 'tenjin new <project_name>' to create a new project"
                      print_info "Or 'cd' to an existing Tenjin project directory"
                      exit 1
                  fi
                  
                  if [ "$VERBOSE" = true ]; then
                      print_info "Executing: mix $task ''${mix_args[*]} ''${args[*]}"
                  fi
                  exec mix "$task" "''${mix_args[@]}" "''${args[@]}"
              fi
          }
          
          # Main command router
          main() {
              # Parse global options first
              parse_global_opts "$@"
              
              # Capture remaining arguments
              local remaining_args=("$@")
              
              # If no command provided, show help
              if [ -z "$COMMAND" ]; then
                  show_help
                  exit 0
              fi
          
              # Check environment
              check_environment
          
              # Remove the command from remaining args
              if [ ''${#remaining_args[@]} -gt 0 ] && [ "''${remaining_args[0]}" = "$COMMAND" ]; then
                  remaining_args=("''${remaining_args[@]:1}")
              fi
          
              # Route to appropriate Mix task
              case "$COMMAND" in
                  # Project management
                  new)
                      if [ ''${#remaining_args[@]} -eq 0 ]; then
                          print_error "Project name required"
                          print_info "Usage: tenjin new <project_name> [options]"
                          exit 1
                      fi
                      run_mix_task "tenjin.new" "''${remaining_args[@]}"
                      ;;
                  init)
                      run_mix_task "tenjin.init" "''${remaining_args[@]}"
                      ;;
          
                  # Supabase management  
                  start)
                      print_info "Starting Supabase development environment..."
                      run_mix_task "tenjin.supabase.start" "''${remaining_args[@]}"
                      ;;
                  stop)
                      print_info "Stopping Supabase development environment..."
                      run_mix_task "tenjin.supabase.stop" "''${remaining_args[@]}"
                      ;;
                  status)
                      run_mix_task "tenjin.supabase.status" "''${remaining_args[@]}"
                      ;;
                  reset)
                      print_warning "This will reset your local database and delete all data!"
                      if [ "$DRY_RUN" != true ]; then
                          read -p "Are you sure you want to continue? [y/N] " -n 1 -r
                          echo
                          if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                              print_info "Reset cancelled"
                              exit 0
                          fi
                      fi
                      run_mix_task "tenjin.supabase.reset" "''${remaining_args[@]}"
                      ;;
          
                  # Schema and migrations
                  generate|gen)
                      if [ ''${#remaining_args[@]} -eq 0 ]; then
                          print_error "Migration name required"
                          print_info "Usage: tenjin generate <migration_name> [options]"
                          exit 1
                      fi
                      run_mix_task "tenjin.gen.migration" "''${remaining_args[@]}"
                      ;;
                  migrate)
                      run_mix_task "tenjin.migrate" "''${remaining_args[@]}"
                      ;;
                  rollback)
                      run_mix_task "tenjin.rollback" "''${remaining_args[@]}"
                      ;;
                  sql)
                      run_mix_task "tenjin.sql.generate" "''${remaining_args[@]}"
                      ;;
          
                  # Development
                  server)
                      print_info "Starting development server..."
                      run_mix_task "tenjin.server" "''${remaining_args[@]}"
                      ;;
                  console)
                      run_mix_task "tenjin.console" "''${remaining_args[@]}"
                      ;;
                  seed)
                      run_mix_task "tenjin.seed" "''${remaining_args[@]}"
                      ;;
          
                  # Utilities
                  validate)
                      run_mix_task "tenjin.schema.validate" "''${remaining_args[@]}"
                      ;;
                  version)
                      run_mix_task "tenjin.version" "''${remaining_args[@]}"
                      ;;
                  help|--help|-h)
                      show_help
                      ;;
          
                  # Unknown command
                  *)
                      print_error "Unknown command: $COMMAND"
                      print_info "Use 'tenjin help' to see available commands"
                      exit 1
                      ;;
              esac
          }
          
          # Run main function with all arguments
          main "$@"
        '';
        
        # Test runner script
        test-runner = pkgs.writeShellScriptBin "tenjin-test" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          TENJIN_ROOT="$(dirname "$(readlink -f "''${BASH_SOURCE[0]}")")/.."
          cd "$TENJIN_ROOT"
          
          echo "🧪 Running Tenjin framework tests..."
          
          # Set test environment
          export MIX_ENV=test
          export PATH="${elixir}/bin:${supabase-cli}/bin:$PATH"
          
          # Function to cleanup on exit
          cleanup() {
            echo "🧹 Cleaning up test environment..."
            
            # Stop any running Supabase instances
            if command -v supabase >/dev/null 2>&1; then
              find /tmp -name "tenjin-test-*" -type d 2>/dev/null | while read -r test_dir; do
                if [ -d "$test_dir/supabase" ]; then
                  echo "  Stopping Supabase in $test_dir..."
                  cd "$test_dir" && supabase stop --no-backup 2>/dev/null || true
                fi
              done
            fi
            
            # Clean up temporary test directories
            rm -rf /tmp/tenjin-test-* 2>/dev/null || true
            
            # Clean up Docker containers if any
            if command -v docker >/dev/null 2>&1; then
              docker ps -a --filter "label=com.supabase.cli" --format "table {{.ID}}" | tail -n +2 | xargs -r docker rm -f 2>/dev/null || true
            fi
          }
          
          # Set trap for cleanup on exit
          trap cleanup EXIT INT TERM
          
          # Install dependencies
          echo "📦 Installing dependencies..."
          mix deps.get
          
          # Compile project
          echo "🔨 Compiling project..."
          mix compile
          
          # Run tests
          echo "🚀 Running unit tests..."
          mix test
          
          # Run integration tests if they exist
          if [ -d "test/integration" ]; then
            echo "🔗 Running integration tests..."
            mix test test/integration/
          fi
          
          echo "✅ All tests passed!"
        '';
        
        # Integration test runner for Tenjin-Supabase projects
        integration-test-runner = pkgs.writeShellScriptBin "tenjin-integration-test" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          PROJECT_DIR="''${1:-}"
          if [ -z "$PROJECT_DIR" ]; then
            echo "Usage: tenjin-integration-test <project-directory>"
            exit 1
          fi
          
          if [ ! -d "$PROJECT_DIR" ]; then
            echo "Error: Project directory '$PROJECT_DIR' does not exist"
            exit 1
          fi
          
          cd "$PROJECT_DIR"
          PROJECT_NAME="$(basename "$PROJECT_DIR")"
          
          echo "🧪 Running integration tests for Tenjin project: $PROJECT_NAME"
          
          # Set environment
          export MIX_ENV=test
          export PATH="${elixir}/bin:${supabase-cli}/bin:$PATH"
          
          # Function to cleanup on exit
          cleanup() {
            echo "🧹 Cleaning up integration test environment for $PROJECT_NAME..."
            
            # Stop Supabase
            if [ -f "supabase/config.toml" ]; then
              echo "  Stopping Supabase..."
              supabase stop --no-backup 2>/dev/null || true
            fi
            
            # Clean up test database
            if [ -f ".env.test" ]; then
              rm -f .env.test
            fi
            
            # Reset to development state
            export MIX_ENV=dev
          }
          
          # Set trap for cleanup
          trap cleanup EXIT INT TERM
          
          # Check if this is a Tenjin project
          if [ ! -f "mix.exs" ] || ! grep -q "tenjin" mix.exs; then
            echo "Error: Not a Tenjin project (mix.exs not found or doesn't include tenjin dependency)"
            exit 1
          fi
          
          # Install dependencies
          echo "📦 Installing dependencies..."
          mix deps.get
          
          # Start Supabase for testing
          if [ -d "supabase" ]; then
            echo "🚀 Starting Supabase..."
            supabase start
            
            # Wait for Supabase to be ready
            echo "⏳ Waiting for Supabase to be ready..."
            sleep 10
          fi
          
          # Run schema validation
          echo "🔍 Validating schema definitions..."
          mix tenjin.schema.validate
          
          # Generate and apply migrations
          echo "📝 Testing migration generation..."
          mix tenjin.gen.migration test_migration
          
          echo "🔄 Applying migrations..."
          mix tenjin.migrate
          
          # Test schema generation
          echo "📊 Testing SQL generation..."
          mix tenjin.sql.generate > /tmp/generated_schema.sql
          
          # Verify generated SQL
          if [ -s /tmp/generated_schema.sql ]; then
            echo "✅ SQL generation successful"
          else
            echo "❌ SQL generation failed"
            exit 1
          fi
          
          # Run application tests if they exist
          if [ -f "test/test_helper.exs" ]; then
            echo "🧪 Running application tests..."
            mix test
          fi
          
          # Test database connectivity
          echo "🔌 Testing database connectivity..."
          mix tenjin.db.status
          
          echo "✅ Integration tests completed successfully!"
        '';
        
        # Development environment setup script
        dev-setup = pkgs.writeShellScriptBin "tenjin-dev-setup" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          echo "🚀 Setting up Tenjin development environment..."
          
          # Set environment
          export PATH="${elixir}/bin:${supabase-cli}/bin:$PATH"
          
          TENJIN_ROOT="$(dirname "$(readlink -f "''${BASH_SOURCE[0]}")")/.."
          cd "$TENJIN_ROOT"
          
          # Install Elixir dependencies
          echo "📦 Installing Elixir dependencies..."
          mix deps.get
          
          # Compile project
          echo "🔨 Compiling Tenjin framework..."
          mix compile
          
          # Check Supabase CLI installation
          echo "🔍 Checking Supabase CLI..."
          if command -v supabase >/dev/null 2>&1; then
            supabase --version
            echo "✅ Supabase CLI ready"
          else
            echo "❌ Supabase CLI not found"
            exit 1
          fi
          
          # Check Docker
          echo "🐳 Checking Docker..."
          if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
            echo "✅ Docker ready"
          else
            echo "⚠️  Docker not running or not installed"
            echo "   Supabase requires Docker to run locally"
          fi
          
          # Create example project for testing
          echo "📝 Creating example project..."
          TEST_PROJECT_DIR="/tmp/tenjin-example"
          rm -rf "$TEST_PROJECT_DIR" 2>/dev/null || true
          
          mix tenjin.new example --path "$TEST_PROJECT_DIR"
          
          if [ -d "$TEST_PROJECT_DIR" ]; then
            echo "✅ Example project created at $TEST_PROJECT_DIR"
            echo ""
            echo "🎉 Development environment ready!"
            echo ""
            echo "Quick start:"
            echo "  cd $TEST_PROJECT_DIR"
            echo "  tenjin supabase.start"
            echo "  tenjin gen.migration initial_schema"
            echo "  tenjin migrate"
            echo ""
            echo "Available commands:"
            echo "  tenjin --help                 # Show all available commands"
            echo "  tenjin-test                   # Run Tenjin framework tests"
            echo "  tenjin-integration-test <dir> # Run integration tests for a project"
          else
            echo "❌ Failed to create example project"
            exit 1
          fi
        '';
        
      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core development tools
            elixir
            supabase-cli
            
            
            # Development utilities
            git
            curl
            jq
            
            # Custom tools
            tenjin-cli
            test-runner
            integration-test-runner
            dev-setup
            
            # Language servers and tools
            elixir-ls
            
          ];
          
          shellHook = ''
            echo "🎯 Tenjin Development Environment"
            echo "=================================="
            echo ""
            echo "Available tools:"
            echo "  elixir        $(elixir --version 2>/dev/null | head -n1 || echo "available")"
            echo "  supabase      $(supabase --version 2>/dev/null || echo "not available")"
            echo ""
            echo "Custom commands:"
            echo "  tenjin-dev-setup              # Set up development environment"
            echo "  tenjin <command>              # Run Tenjin CLI commands"
            echo "  tenjin-test                   # Run framework tests"
            echo "  tenjin-integration-test <dir> # Run integration tests"
            echo ""
            echo "Getting started:"
            echo "  1. Run 'tenjin-dev-setup' to initialize the development environment"
            echo "  2. Create a new project with 'tenjin new my_app'"
            echo "  3. Start developing with full Supabase integration!"
            echo ""
            
            # Set up environment variables
            export MIX_ENV=dev
            export TENJIN_DEV=true
            export TENJIN_HOME="$PWD"
            
            # Add current directory to PATH for local development
            export PATH="$PWD:$PATH"
            
            # Ensure mix is available
            if command -v mix >/dev/null 2>&1; then
              echo "✅ Ready to develop with Tenjin!"
            else
              echo "❌ Mix not found. Please check Elixir installation."
            fi
            echo ""
          '';
        };
        
        # Packages that can be installed
        packages = {
          inherit tenjin-cli test-runner integration-test-runner dev-setup;
          default = tenjin-cli;
        };
        
        # Apps that can be run with `nix run`
        apps = {
          default = flake-utils.lib.mkApp {
            drv = tenjin-cli;
          };
          
          tenjin = flake-utils.lib.mkApp {
            drv = tenjin-cli;
          };
          
          test = flake-utils.lib.mkApp {
            drv = test-runner;
          };
          
          integration-test = flake-utils.lib.mkApp {
            drv = integration-test-runner;
          };
          
          dev-setup = flake-utils.lib.mkApp {
            drv = dev-setup;
          };
        };
        
        # Checks that run in CI
        checks = {
          tenjin-test = pkgs.stdenv.mkDerivation {
            name = "tenjin-test";
            src = ./.;
            
            buildInputs = [ elixir supabase-cli ];
            
            buildPhase = ''
              export MIX_ENV=test
              export HOME=$TMPDIR
              
              # Install dependencies
              mix deps.get
              
              # Compile
              mix compile
              
              # Run tests
              mix test
            '';
            
            installPhase = ''
              mkdir -p $out
              echo "Tests passed" > $out/result
            '';
          };
        };
      }
    );
}

