defmodule Tenjin.SchemaTest do
  use ExUnit.Case

  # Test schema module
  defmodule TestSchema do
    use Tenjin.Schema

    table "users" do
      field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
      field :email, :text, unique: true, null: false
      field :name, :text
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

      belongs_to :organization, "organizations"
      has_many :posts, foreign_key: :author_id
    end

    table "posts" do
      field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
      field :title, :text, null: false
      field :content, :text
      field :author_id, :uuid, references: "users(id)", on_delete: :cascade
      field :published, :boolean, default: false

      enable_rls()

      policy :select, "Published posts are public" do
        "published = true"
      end

      belongs_to :author, "users"
    end

    function "slugify", [:text], :text do
      """
      DECLARE
        result text;
      BEGIN
        result := lower(trim($1));
        result := regexp_replace(result, '[^a-z0-9\\-_]+', '-', 'gi');
        RETURN result;
      END;
      """
    end

    view "published_posts_with_authors" do
      """
      SELECT p.id, p.title, u.name as author_name
      FROM posts p
      JOIN users u ON p.author_id = u.id
      WHERE p.published = true
      """
    end

    custom_type "post_status", :enum, values: ["draft", "published", "archived"]

    storage_bucket "avatars" do
      public true
      file_size_limit "1MB"
      allowed_mime_types ["image/jpeg", "image/png"]

      policy :select, "Avatar images are publicly readable" do
        "true"
      end
    end
  end

  describe "schema compilation" do
    test "schema module compiles without errors" do
      assert Code.ensure_loaded?(TestSchema)
    end

    test "schema module has required functions" do
      assert function_exported?(TestSchema, :__schema__, 0)
      assert function_exported?(TestSchema, :__tables__, 0)
      assert function_exported?(TestSchema, :__functions__, 0)
      assert function_exported?(TestSchema, :__views__, 0)
      assert function_exported?(TestSchema, :__storage_buckets__, 0)
      assert function_exported?(TestSchema, :__custom_types__, 0)
    end
  end

  describe "table definitions" do
    test "returns correct table definitions" do
      tables = TestSchema.__tables__()
      
      assert length(tables) == 2
      
      users_table = Enum.find(tables, &(&1.name == "users"))
      posts_table = Enum.find(tables, &(&1.name == "posts"))
      
      assert users_table
      assert posts_table
      
      # Check users table structure
      assert users_table.rls_enabled == true
      assert length(users_table.fields) == 5
      assert length(users_table.policies) == 2
      assert length(users_table.indexes) == 2
      assert length(users_table.triggers) == 1
      assert length(users_table.relationships) == 2
    end

    test "field definitions are correct" do
      tables = TestSchema.__tables__()
      users_table = Enum.find(tables, &(&1.name == "users"))
      
      id_field = Enum.find(users_table.fields, &(&1.name == :id))
      email_field = Enum.find(users_table.fields, &(&1.name == :email))
      
      assert id_field.type == :uuid
      assert id_field.options[:primary_key] == true
      assert id_field.options[:default] == "gen_random_uuid()"
      
      assert email_field.type == :text
      assert email_field.options[:unique] == true
      assert email_field.options[:null] == false
    end

    test "policy definitions are correct" do
      tables = TestSchema.__tables__()
      users_table = Enum.find(tables, &(&1.name == "users"))
      
      select_policy = Enum.find(users_table.policies, &(&1.action == :select))
      update_policy = Enum.find(users_table.policies, &(&1.action == :update))
      
      assert select_policy.description == "Users can view their own profile"
      assert select_policy.condition == "auth.uid() = id"
      
      assert update_policy.description == "Users can update their own profile"
      assert update_policy.condition == "auth.uid() = id"
    end

    test "index definitions are correct" do
      tables = TestSchema.__tables__()
      users_table = Enum.find(tables, &(&1.name == "users"))
      
      email_index = Enum.find(users_table.indexes, &(&1.fields == [:email]))
      created_at_index = Enum.find(users_table.indexes, &(&1.fields == [:created_at]))
      
      assert email_index.options[:unique] == true
      refute created_at_index.options[:unique]
    end
  end

  describe "function definitions" do
    test "returns correct function definitions" do
      functions = TestSchema.__functions__()
      
      assert length(functions) == 1
      
      slugify_fn = hd(functions)
      assert slugify_fn.name == "slugify"
      assert slugify_fn.args == [:text]
      assert slugify_fn.return_type == :text
      assert String.contains?(slugify_fn.body, "DECLARE")
    end
  end

  describe "view definitions" do
    test "returns correct view definitions" do
      views = TestSchema.__views__()
      
      assert length(views) == 1
      
      posts_view = hd(views)
      assert posts_view.name == "published_posts_with_authors"
      assert String.contains?(posts_view.query, "SELECT")
      assert String.contains?(posts_view.query, "JOIN")
    end
  end

  describe "custom type definitions" do
    test "returns correct custom type definitions" do
      types = TestSchema.__custom_types__()
      
      assert length(types) == 1
      
      status_type = hd(types)
      assert status_type.name == "post_status"
      assert status_type.type == :enum
      assert status_type.options[:values] == ["draft", "published", "archived"]
    end
  end

  describe "storage bucket definitions" do
    test "returns correct storage bucket definitions" do
      buckets = TestSchema.__storage_buckets__()
      
      assert length(buckets) == 1
      
      avatars_bucket = hd(buckets)
      assert avatars_bucket.name == "avatars"
      assert avatars_bucket.options[:public] == true
      assert avatars_bucket.options[:file_size_limit] == "1MB"
      assert avatars_bucket.options[:allowed_mime_types] == ["image/jpeg", "image/png"]
      assert length(avatars_bucket.policies) == 1
    end
  end

  describe "complete schema" do
    test "returns complete schema structure" do
      schema = TestSchema.__schema__()
      
      assert Map.has_key?(schema, :tables)
      assert Map.has_key?(schema, :functions)
      assert Map.has_key?(schema, :views)
      assert Map.has_key?(schema, :storage_buckets)
      assert Map.has_key?(schema, :custom_types)
      
      assert length(schema.tables) == 2
      assert length(schema.functions) == 1
      assert length(schema.views) == 1
      assert length(schema.storage_buckets) == 1
      assert length(schema.custom_types) == 1
    end
  end
end
