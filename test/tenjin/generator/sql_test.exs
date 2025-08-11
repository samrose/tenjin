defmodule Tenjin.Generator.SQLTest do
  use ExUnit.Case

  alias Tenjin.Generator.SQL

  describe "generate_table/1" do
    test "generates basic table SQL" do
      table_def = %{
        name: "users",
        fields: [
          %{name: :id, type: :uuid, options: [primary_key: true, default: "gen_random_uuid()"]},
          %{name: :email, type: :text, options: [unique: true, null: false]},
          %{name: :name, type: :text, options: []}
        ],
        options: []
      }

      sql = SQL.generate_table(table_def)

      assert String.contains?(sql, "CREATE TABLE users")
      assert String.contains?(sql, "id uuid DEFAULT gen_random_uuid() PRIMARY KEY")
      assert String.contains?(sql, "email text NOT NULL UNIQUE")
      assert String.contains?(sql, "name text")
    end

    test "generates table with comment" do
      table_def = %{
        name: "users",
        fields: [
          %{name: :id, type: :uuid, options: [primary_key: true]}
        ],
        options: [comment: "User accounts table"]
      }

      sql = SQL.generate_table(table_def)

      assert String.contains?(sql, "CREATE TABLE users")
      assert String.contains?(sql, "COMMENT ON TABLE users IS 'User accounts table';")
    end

    test "generates table with foreign key references" do
      table_def = %{
        name: "posts",
        fields: [
          %{name: :id, type: :uuid, options: [primary_key: true]},
          %{name: :author_id, type: :uuid, options: [references: "users(id)", on_delete: :cascade]}
        ],
        options: []
      }

      sql = SQL.generate_table(table_def)

      assert String.contains?(sql, "author_id uuid REFERENCES users(id) ON DELETE CASCADE")
    end

    test "generates table with generated columns" do
      table_def = %{
        name: "users",
        fields: [
          %{name: :first_name, type: :text, options: []},
          %{name: :last_name, type: :text, options: []},
          %{name: :full_name, type: :text, options: [generated: "first_name || ' ' || last_name"]}
        ],
        options: []
      }

      sql = SQL.generate_table(table_def)

      assert String.contains?(sql, "full_name text GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED")
    end
  end

  describe "generate_field/1" do
    test "generates basic field" do
      field = %{name: :name, type: :text, options: []}
      
      result = SQL.generate_field(field)
      
      assert result == "name text"
    end

    test "generates field with constraints" do
      field = %{name: :email, type: :text, options: [null: false, unique: true]}
      
      result = SQL.generate_field(field)
      
      assert result == "email text NOT NULL UNIQUE"
    end

    test "generates field with default value" do
      field = %{name: :created_at, type: :timestamptz, options: [default: "now()"]}
      
      result = SQL.generate_field(field)
      
      assert result == "created_at timestamptz DEFAULT now()"
    end
  end

  describe "generate_indexes/1" do
    test "generates single column index" do
      table_def = %{
        name: "users",
        indexes: [
          %{fields: [:email], options: []}
        ]
      }

      sql = SQL.generate_indexes(table_def)

      assert String.contains?(sql, "CREATE INDEX users_email_idx ON users (email);")
    end

    test "generates unique index" do
      table_def = %{
        name: "users", 
        indexes: [
          %{fields: [:email], options: [unique: true]}
        ]
      }

      sql = SQL.generate_indexes(table_def)

      assert String.contains?(sql, "CREATE UNIQUE INDEX users_email_unique ON users (email);")
    end

    test "generates composite index" do
      table_def = %{
        name: "posts",
        indexes: [
          %{fields: [:author_id, :created_at], options: []}
        ]
      }

      sql = SQL.generate_indexes(table_def)

      assert String.contains?(sql, "CREATE INDEX posts_author_id_created_at_idx ON posts (author_id, created_at);")
    end

    test "generates partial index" do
      table_def = %{
        name: "posts",
        indexes: [
          %{fields: [:title], options: [where: "published = true"]}
        ]
      }

      sql = SQL.generate_indexes(table_def)

      assert String.contains?(sql, "CREATE INDEX posts_title_idx ON posts (title) WHERE published = true;")
    end
  end

  describe "generate_function/1" do
    test "generates basic function" do
      function_def = %{
        name: "slugify",
        args: [:text],
        return_type: :text,
        body: "RETURN lower($1);",
        options: []
      }

      sql = SQL.generate_function(function_def)

      assert String.contains?(sql, "CREATE OR REPLACE FUNCTION slugify($1 text)")
      assert String.contains?(sql, "RETURNS text")
      assert String.contains?(sql, "RETURN lower($1);")
      assert String.contains?(sql, "$$ LANGUAGE plpgsql;")
    end

    test "generates function with multiple arguments" do
      function_def = %{
        name: "add_numbers",
        args: [:integer, :integer],
        return_type: :integer,
        body: "RETURN $1 + $2;",
        options: []
      }

      sql = SQL.generate_function(function_def)

      assert String.contains?(sql, "CREATE OR REPLACE FUNCTION add_numbers($1 integer, $2 integer)")
      assert String.contains?(sql, "RETURNS integer")
    end

    test "generates function with volatility" do
      function_def = %{
        name: "get_current_time",
        args: [],
        return_type: :timestamptz,
        body: "RETURN now();",
        options: [volatility: :volatile]
      }

      sql = SQL.generate_function(function_def)

      assert String.contains?(sql, "RETURNS timestamptz VOLATILE")
    end
  end

  describe "generate_view/1" do
    test "generates basic view" do
      view_def = %{
        name: "active_users",
        query: "SELECT * FROM users WHERE active = true",
        options: []
      }

      sql = SQL.generate_view(view_def)

      assert String.contains?(sql, "CREATE VIEW active_users AS")
      assert String.contains?(sql, "SELECT * FROM users WHERE active = true")
    end

    test "generates materialized view" do
      view_def = %{
        name: "user_stats",
        query: "SELECT COUNT(*) as total FROM users",
        options: [materialized: true]
      }

      sql = SQL.generate_view(view_def)

      assert String.contains?(sql, "CREATE MATERIALIZED VIEW user_stats AS")
    end

    test "generates view with comment" do
      view_def = %{
        name: "active_users",
        query: "SELECT * FROM users WHERE active = true",
        options: [comment: "View of active users only"]
      }

      sql = SQL.generate_view(view_def)

      assert String.contains?(sql, "COMMENT ON VIEW active_users IS 'View of active users only';")
    end
  end

  describe "generate_custom_type/1" do
    test "generates enum type" do
      type_def = %{
        name: "user_role",
        type: :enum,
        options: [values: ["admin", "user", "guest"]]
      }

      sql = SQL.generate_custom_type(type_def)

      assert String.contains?(sql, "CREATE TYPE user_role AS ENUM")
      assert String.contains?(sql, "'admin', 'user', 'guest'")
    end

    test "generates composite type" do
      type_def = %{
        name: "address",
        type: :composite,
        options: [fields: [street: :text, city: :text, zip: :text]]
      }

      sql = SQL.generate_custom_type(type_def)

      assert String.contains?(sql, "CREATE TYPE address AS")
      assert String.contains?(sql, "street text, city text, zip text")
    end

    test "generates domain type" do
      type_def = %{
        name: "email",
        type: :domain,
        options: [base_type: :text, constraint: "VALUE ~ '^[^@]+@[^@]+$'"]
      }

      sql = SQL.generate_custom_type(type_def)

      assert String.contains?(sql, "CREATE DOMAIN email AS text")
      assert String.contains?(sql, "CONSTRAINT email_check CHECK (VALUE ~ '^[^@]+@[^@]+$')")
    end
  end

  describe "generate_storage_bucket/1" do
    test "generates storage bucket creation SQL" do
      bucket_def = %{
        name: "avatars",
        options: [
          public: true,
          file_size_limit: "1MB",
          allowed_mime_types: ["image/jpeg", "image/png"]
        ]
      }

      sql = SQL.generate_storage_bucket(bucket_def)

      assert String.contains?(sql, "INSERT INTO storage.buckets")
      assert String.contains?(sql, "'avatars'")
      assert String.contains?(sql, "true") # public
      assert String.contains?(sql, "1048576") # 1MB in bytes
      assert String.contains?(sql, "ARRAY['image/jpeg', 'image/png']")
    end

    test "generates private storage bucket" do
      bucket_def = %{
        name: "private_files",
        options: [public: false]
      }

      sql = SQL.generate_storage_bucket(bucket_def)

      assert String.contains?(sql, "false") # not public
    end
  end

  describe "enable_rls/1" do
    test "generates RLS enable statement" do
      sql = SQL.enable_rls("users")
      
      assert sql == "ALTER TABLE users ENABLE ROW LEVEL SECURITY;"
    end
  end
end
