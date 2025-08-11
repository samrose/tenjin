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
    
    trigger :update_updated_at, on: :update do
      "updated_at = now()"
    end
    
    has_many :posts, foreign_key: :author_id
  end

  table "posts" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :title, :text, null: false
    field :content, :text
    field :excerpt, :text
    field :slug, :text, unique: true
    field :author_id, :uuid, references: "users(id)", on_delete: :cascade
    field :published, :boolean, default: false
    field :published_at, :timestamptz
    field :created_at, :timestamptz, default: "now()"
    field :updated_at, :timestamptz, default: "now()"
    
    enable_rls()
    
    policy :select, "Published posts are public" do
      "published = true"
    end
    
    policy :select, "Authors can see their own posts", for: :authenticated do
      "auth.uid() = author_id"
    end
    
    policy :insert, "Authors can create posts" do
      "auth.uid() = author_id"
    end
    
    policy :update, "Authors can edit their posts" do
      "auth.uid() = author_id"
    end
    
    policy :delete, "Authors can delete their posts" do
      "auth.uid() = author_id"
    end
    
    belongs_to :author, "users"
    
    index [:slug], unique: true
    index [:author_id]
    index [:published, :published_at]
    index [:created_at]
    
    trigger :update_updated_at, on: :update do
      "updated_at = now()"
    end
    
    trigger :generate_slug, on: [:insert, :update] do
      """
      IF NEW.slug IS NULL OR NEW.slug = '' THEN
        NEW.slug = slugify(NEW.title);
      END IF;
      """
    end
  end

  # Custom database functions
  function "slugify", [:text], :text do
    """
    DECLARE
      result text;
    BEGIN
      result := lower(trim($1));
      result := regexp_replace(result, '[^a-z0-9\\-_]+', '-', 'gi');
      result := regexp_replace(result, '-{2,}', '-', 'g');
      result := trim(result, '-');
      RETURN result;
    END;
    """
  end

  # Database views for complex queries
  view "published_posts_with_authors" do
    """
    SELECT 
      p.id, p.title, p.slug, p.excerpt, p.published_at,
      u.name as author_name, u.avatar_url as author_avatar
    FROM posts p
    JOIN users u ON p.author_id = u.id  
    WHERE p.published = true
    ORDER BY p.published_at DESC
    """
  end

  # File storage buckets
  storage_bucket "avatars" do
    public true
    file_size_limit "2MB"
    allowed_mime_types ["image/jpeg", "image/png", "image/webp"]
    
    policy :select, "Avatars are publicly readable" do
      "true"
    end
    
    policy :insert, "Users can upload their own avatar" do
      "auth.uid()::text = (storage.foldername(name))[1]"
    end
  end
end
```

## Generate and Apply Migrations

```bash
# Generate migration from schema changes
tenjin generate initial_schema
# or: nix run .#tenjin generate initial_schema

# Apply migrations to database  
tenjin migrate
# or: nix run .#tenjin migrate

# Use database diff for incremental changes
tenjin generate add_comments --diff
# or: nix run .#tenjin generate add_comments --diff
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
tenjin new <project_name>    # Create new Tenjin project
tenjin init                  # Initialize Tenjin in existing project
```

### Supabase Management
```bash
tenjin start                 # Start local Supabase
tenjin stop                  # Stop local Supabase
tenjin status                # Check Supabase status  
tenjin reset                 # Reset local database
```

### Schema & Migrations
```bash
tenjin generate <name>       # Generate migration from schema
tenjin migrate               # Apply pending migrations
tenjin rollback              # Rollback last migration
tenjin sql                   # Generate SQL from current schema
```

### Development
```bash
tenjin server                # Start development server
tenjin console               # Interactive console  
tenjin seed                  # Run database seeds
tenjin validate              # Validate schema definitions
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

- [Blog Example](examples/blog/) - Complete blog with users, posts, comments
- [Todo App](examples/todo_app/) - Todo application with real-time features
- [E-commerce](examples/ecommerce/) - Complex e-commerce schema

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
   git clone https://github.com/tenjin-framework/tenjin.git
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
