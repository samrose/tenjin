# Tenjin

[![Hex.pm](https://img.shields.io/hexpm/v/tenjin.svg)](https://hex.pm/packages/tenjin)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/tenjin/)
[![Nix Flake](https://img.shields.io/badge/nix-flake-blue)](https://nixos.org/)

**Tenjin** is an Elixir framework that bridges the gap between Elixir's expressive syntax and Supabase's powerful backend-as-a-service platform. Write your database schemas, RLS policies, and functions in Elixir DSL, and let Tenjin generate production-ready PostgreSQL migrations for Supabase.

🎯 **Database-first development with Elixir elegance**  
🚀 **Full Supabase feature parity**  
🔒 **Security-first with built-in RLS support**  
⚡ **Zero-SQL required**  
🧪 **Comprehensive testing framework**

## Features

- 🔥 **Elixir DSL** - Define database schemas, RLS policies, and functions using Elixir syntax
- 🚀 **Automatic SQL Generation** - Generate production-ready SQL migrations from Elixir code
- 🔒 **Security First** - Built-in Row Level Security (RLS) policy management
- 📦 **Supabase Integration** - Seamless integration with Supabase CLI and features
- 🛠️ **Developer Experience** - Rich CLI tools and helpful error messages
- 🧪 **Testing Support** - Comprehensive testing utilities for database schemas

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled (recommended)
- OR [Elixir](https://elixir-lang.org/install.html) 1.14+ with Mix
- [Docker](https://www.docker.com/) (for Supabase)
- [Supabase CLI](https://supabase.com/docs/guides/cli)

### Using Nix Flakes (Recommended)

1. **Clone and enter the development environment:**
   ```bash
   git clone https://github.com/tenjin-framework/tenjin.git
   cd tenjin
   nix develop
   ```

2. **Set up the development environment:**
   ```bash
   tenjin-dev-setup
   ```

3. **Create a new project:**
   ```bash
   nix run .#tenjin new my_blog
   cd my_blog
   ```

4. **Start Supabase:**
   ```bash
   nix run .#tenjin start
   ```

### Traditional Installation

1. **Add tenjin to your dependencies:**
   ```elixir
   def deps do
     [
       {:tenjin, "~> 0.1.0"}
     ]
   end
   ```

2. **Create a new project:**
   ```bash
   mix tenjin.new my_blog
   cd my_blog
   ```

3. **Start Supabase:**
   ```bash
   mix tenjin.supabase.start
   ```

## Schema Definition

Define your database schema using Tenjin's expressive Elixir DSL:

```elixir
defmodule MyBlog.Schema do
  use Tenjin.Schema

  # Users table with authentication and RLS
  table "users" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :email, :text, unique: true, null: false
    field :name, :text
    field :avatar_url, :text
    field :created_at, :timestamptz, default: "now()"
    field :updated_at, :timestamptz, default: "now()"

    enable_rls()

    policy :select, "Users can view their own profile" do
      "auth.uid() = id"
    end

    policy :update, "Users can update their own profile" do
      "auth.uid() = id"
    end

    index [:email], unique: true
    index [:created_at]
  end

  # Blog posts table
  table "posts" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :title, :text, null: false
    field :slug, :text, unique: true, null: false
    field :content, :text
    field :excerpt, :text
    field :author_id, :uuid, references: "users(id)", on_delete: :cascade
    field :published, :boolean, default: false
    field :published_at, :timestamptz
    field :created_at, :timestamptz, default: "now()"
    field :updated_at, :timestamptz, default: "now()"

    enable_rls()

    policy :select, "Published posts are viewable by all" do
      "published = true"
    end

    policy :select, "Authors can view their own posts" do
      "auth.uid() = author_id"
    end

    policy :insert, "Authenticated users can create posts" do
      "auth.uid() = author_id"
    end

    policy :update, "Authors can update their own posts" do
      "auth.uid() = author_id"
    end

    policy :delete, "Authors can delete their own posts" do
      "auth.uid() = author_id"
    end

    index [:author_id]
    index [:published, :created_at]
    index [:slug], unique: true
  end

  # Categories for organizing posts
  table "categories" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :name, :text, unique: true, null: false
    field :description, :text
    field :created_at, :timestamptz, default: "now()"

    enable_rls()

    policy :select, "Categories are publicly viewable" do
      "true"
    end

    index [:name], unique: true
  end

  # Many-to-many relationship between posts and categories
  table "post_categories" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :post_id, :uuid, references: "posts(id)", on_delete: :cascade
    field :category_id, :uuid, references: "categories(id)", on_delete: :cascade
    field :created_at, :timestamptz, default: "now()"

    enable_rls()

    policy :select, "Post categories follow post visibility" do
      "EXISTS (SELECT 1 FROM posts WHERE id = post_id AND (published = true OR auth.uid() = author_id))"
    end

    policy :insert, "Authors can categorize their posts" do
      "EXISTS (SELECT 1 FROM posts WHERE id = post_id AND auth.uid() = author_id)"
    end

    policy :delete, "Authors can remove categories from their posts" do
      "EXISTS (SELECT 1 FROM posts WHERE id = post_id AND auth.uid() = author_id)"
    end

    index [:post_id, :category_id], unique: true
    index [:category_id]
  end

  # Comments on posts
  table "comments" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :post_id, :uuid, references: "posts(id)", on_delete: :cascade
    field :author_id, :uuid, references: "users(id)", on_delete: :cascade
    field :content, :text, null: false
    field :created_at, :timestamptz, default: "now()"
    field :updated_at, :timestamptz, default: "now()"

    enable_rls()

    policy :select, "Comments are viewable on published posts" do
      "EXISTS (SELECT 1 FROM posts WHERE id = post_id AND published = true)"
    end

    policy :insert, "Authenticated users can comment" do
      "auth.uid() = author_id"
    end

    policy :update, "Users can update their own comments" do
      "auth.uid() = author_id"
    end

    policy :delete, "Users can delete their own comments" do
      "auth.uid() = author_id"
    end

    index [:post_id, :created_at]
    index [:author_id]
  end
end
```

## Generate and Apply Migrations

```bash
# Generate migration from schema changes
mix tenjin.gen.migration initial_schema
# or: nix run .#tenjin gen.migration initial_schema

# Apply migrations to database  
mix tenjin.migrate
# or: nix run .#tenjin migrate

# Start Supabase development environment
mix tenjin.supabase.start
# or: nix run .#tenjin supabase.start
```

## Development Workflow

1. **Define your schema** in `lib/my_app/schema.ex`
2. **Generate migrations** from schema changes
3. **Apply migrations** to your local Supabase instance
4. **Iterate** - modify schema, generate new migrations, apply
5. **Deploy** to Supabase Cloud when ready

## CLI Commands

### Project Management
```bash
mix tenjin.new <project_name>    # Create new Tenjin project
mix tenjin.init                  # Initialize Tenjin in existing project
```

### Supabase Management
```bash
mix tenjin.supabase.start        # Start local Supabase
mix tenjin.supabase.stop         # Stop local Supabase
mix tenjin.supabase.status       # Check Supabase status  
mix tenjin.supabase.reset        # Reset local database
```

### Schema & Migrations
```bash
mix tenjin.gen.migration <name>  # Generate migration from schema
mix tenjin.migrate               # Apply pending migrations
mix tenjin.migrate --local       # Apply to local database explicitly
```

## Testing

Tenjin includes a comprehensive testing framework:

```bash
# Run framework tests
nix run .#test

# Run integration tests for a project  
nix run .#integration-test ./my_project

# Run project-specific tests
cd my_project && mix test
```

## Examples

- [Blog Example](examples/blog/) - Complete blog with users, posts, categories, and comments

## Documentation

- [Schema DSL Reference](docs/schema_dsl.md) - Complete DSL documentation
- [RLS Policies](docs/rls_policies.md) - Row Level Security guide
- [Migration System](docs/migrations.md) - Migration workflow
- [Testing Guide](docs/testing.md) - Testing your schemas
- [Deployment](docs/deployment.md) - Deploy to production

## Architecture

Tenjin integrates with Supabase CLI's native workflow:

1. **Supabase CLI** handles migration file creation and database operations
2. **Tenjin** translates Elixir DSL to SQL content for those migration files
3. **Your schema definitions** drive the entire process

This approach gives you:
- Full compatibility with Supabase tooling
- Type-safe schema definitions in Elixir
- Automatic SQL generation with best practices
- Database-first development workflow

## Development Environment

Tenjin includes a complete Nix-based development environment:

```bash
# Enter development shell
nix develop

# Available commands in dev environment:
tenjin-dev-setup             # Initialize development environment
tenjin-test                  # Run framework tests
tenjin-integration-test      # Run integration tests
tenjin <command>             # Tenjin CLI commands
```

The development environment includes:
- Elixir with all required dependencies
- Supabase CLI
- Docker and Docker Compose
- PostgreSQL client tools
- Development utilities and language servers

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/tenjin.git
   cd tenjin
   ```

2. **Enter development environment:**
   ```bash
   nix develop
   ```

3. **Set up development environment:**
   ```bash
   tenjin-dev-setup
   ```

4. **Run tests:**
   ```bash
   tenjin-test
   ```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Supabase](https://supabase.com/) for the amazing backend-as-a-service platform
- [Elixir](https://elixir-lang.org/) community for the inspiration and tools
- [Phoenix Framework](https://phoenixframework.org/) for DSL design patterns
