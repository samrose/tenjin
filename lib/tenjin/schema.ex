defmodule Tenjin.Schema do
  @moduledoc """
  Core DSL for defining database schemas in Tenjin.

  This module provides macros for declaratively defining database tables,
  fields, indexes, RLS policies, triggers, and relationships using Elixir syntax.

  ## Example

      defmodule MyApp.Schema do
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
          field :author_id, :uuid, references: "users(id)", on_delete: :cascade
          field :published, :boolean, default: false
          field :created_at, :timestamptz, default: "now()"

          enable_rls()

          policy :select, "Published posts are viewable by all" do
            "published = true"
          end

          policy :insert, "Authenticated users can create posts" do
            "auth.uid() = author_id"
          end

          index [:author_id]
          index [:published, :created_at]
        end
      end
  """

  @doc """
  Sets up the schema DSL in the using module.
  """
  defmacro __using__(_opts) do
    quote do
      import Tenjin.Schema
      
      Module.register_attribute(__MODULE__, :tables, accumulate: true)
      Module.register_attribute(__MODULE__, :functions, accumulate: true)
      Module.register_attribute(__MODULE__, :views, accumulate: true)
      Module.register_attribute(__MODULE__, :storage_buckets, accumulate: true)
      Module.register_attribute(__MODULE__, :custom_types, accumulate: true)
      
      @before_compile Tenjin.Schema
    end
  end

  @doc """
  Defines a database table with the given name and block of field/policy definitions.

  ## Options

    * `:comment` - A comment for the table

  ## Example

      table "users" do
        field :id, :uuid, primary_key: true
        field :email, :text, unique: true
        
        enable_rls()
        policy :select, "Public read access", do: "true"
      end
  """
  defmacro table(name, opts \\ [], do: block) do
    quote do
      @current_table %{
        name: unquote(name),
        fields: [],
        indexes: [],
        policies: [],
        triggers: [],
        relationships: [],
        rls_enabled: false,
        options: unquote(opts)
      }
      
      unquote(block)
      
      @tables @current_table
      @current_table nil
    end
  end

  @doc """
  Defines a field in the current table.

  ## Options

    * `:null` - Whether the field can be null (default: true)
    * `:default` - Default value for the field
    * `:primary_key` - Whether this is a primary key field (default: false)
    * `:unique` - Whether this field should be unique (default: false)
    * `:references` - Foreign key reference in the format "table(column)"
    * `:on_delete` - Action on delete (:cascade, :restrict, :set_null, :set_default)
    * `:on_update` - Action on update (:cascade, :restrict, :set_null, :set_default)
    * `:generated` - For computed/generated columns
    * `:comment` - Comment for the field
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      unless @current_table do
        raise "field/3 can only be used inside a table/2 block"
      end

      field_def = %{
        name: unquote(name),
        type: unquote(type),
        options: unquote(opts)
      }

      @current_table Map.update!(@current_table, :fields, &[field_def | &1])
    end
  end

  @doc """
  Enables Row Level Security (RLS) for the current table.
  """
  defmacro enable_rls do
    quote do
      unless @current_table do
        raise "enable_rls/0 can only be used inside a table/2 block"
      end

      @current_table Map.put(@current_table, :rls_enabled, true)
    end
  end

  @doc """
  Defines a Row Level Security policy for the current table.

  ## Parameters

    * `operation` - The database operation (:select, :insert, :update, :delete, :all)
    * `name` - Human-readable name for the policy
    * `block` - Block that returns the policy expression as a string

  ## Example

      policy :select, "Users can view their own posts" do
        "auth.uid() = author_id"
      end
  """
  defmacro policy(operation, name, do: block) do
    quote do
      unless @current_table do
        raise "policy/3 can only be used inside a table/2 block"
      end

      policy_def = %{
        action: unquote(operation),
        description: unquote(name),
        condition: unquote(block),
        options: []
      }

      @current_table Map.update!(@current_table, :policies, &[policy_def | &1])
    end
  end

  @doc """
  Defines an index on the current table.

  ## Options

    * `:unique` - Whether this is a unique index (default: false)
    * `:method` - Index method (:btree, :hash, :gist, :gin, etc.)
    * `:where` - Partial index condition
    * `:comment` - Comment for the index

  ## Examples

      index [:email], unique: true
      index [:created_at]
      index [:title], method: :gin
  """
  defmacro index(fields, opts \\ []) do
    quote do
      unless @current_table do
        raise "index/2 can only be used inside a table/2 block"
      end

      index_def = %{
        fields: unquote(fields),
        options: unquote(opts)
      }

      @current_table Map.update!(@current_table, :indexes, &[index_def | &1])
    end
  end

  @doc """
  Defines a database trigger on the current table.

  ## Parameters

    * `name` - The trigger name
    * `event` - When to fire (:before, :after, :instead_of)
    * `operations` - List of operations ([:insert, :update, :delete])
    * `function_name` - The trigger function to call

  ## Example

      trigger "update_timestamp", :before, [:update], "update_updated_at_column"
  """
  defmacro trigger(name, event, operations, function_name, opts \\ []) do
    quote do
      unless @current_table do
        raise "trigger/5 can only be used inside a table/2 block"
      end

      trigger_def = %{
        name: unquote(name),
        event: unquote(event),
        operations: unquote(operations),
        function_name: unquote(function_name),
        options: unquote(opts)
      }

      @current_table Map.update!(@current_table, :triggers, &[trigger_def | &1])
    end
  end

  @doc """
  Defines a relationship to another table.

  ## Types

    * `:belongs_to` - This table has a foreign key to another table
    * `:has_one` - One-to-one relationship
    * `:has_many` - One-to-many relationship
    * `:many_to_many` - Many-to-many relationship through a join table

  ## Options

    * `:foreign_key` - The foreign key field name
    * `:references` - The referenced field (default: :id)
    * `:through` - For many-to-many, the join table
    * `:join_keys` - For many-to-many, the keys in the join table

  ## Examples

      belongs_to :user, foreign_key: :user_id
      has_many :posts, foreign_key: :author_id  
      many_to_many :tags, through: :post_tags
  """
  defmacro belongs_to(name, opts \\ []) do
    add_relationship(:belongs_to, name, opts)
  end

  defmacro has_one(name, opts \\ []) do
    add_relationship(:has_one, name, opts)
  end

  defmacro has_many(name, opts \\ []) do
    add_relationship(:has_many, name, opts)
  end

  defmacro many_to_many(name, opts \\ []) do
    add_relationship(:many_to_many, name, opts)
  end

  defp add_relationship(type, name, opts) do
    quote do
      unless @current_table do
        raise "#{unquote(type)}/2 can only be used inside a table/2 block"
      end

      relationship_def = %{
        type: unquote(type),
        name: unquote(name),
        options: unquote(opts)
      }

      @current_table Map.update!(@current_table, :relationships, &[relationship_def | &1])
    end
  end

  @doc """
  Defines a database function.

  ## Examples

      function "updated_at_trigger", returns: :trigger do
        \"\"\"
        BEGIN
          NEW.updated_at = NOW();
          RETURN NEW;
        END;
        \"\"\"
      end
  """
  defmacro function(name, opts \\ [], do: body) do
    quote do
      function_def = %{
        name: unquote(name),
        body: unquote(body),
        options: unquote(opts)
      }

      @functions function_def
    end
  end

  @doc """
  Defines a database view.

  ## Examples

      view "active_users" do
        \"\"\"
        SELECT * FROM users WHERE active = true
        \"\"\"
      end
  """
  defmacro view(name, opts \\ [], do: query) do
    quote do
      view_def = %{
        name: unquote(name),
        query: unquote(query),
        options: unquote(opts)
      }

      @views view_def
    end
  end

  @doc """
  Defines a custom PostgreSQL type.

  ## Examples

      custom_type "post_status", :enum, values: ["draft", "published", "archived"]
  """
  defmacro custom_type(name, type, opts \\ []) do
    quote do
      type_def = %{
        name: unquote(name),
        type: unquote(type),
        options: unquote(opts)
      }

      @custom_types type_def
    end
  end

  @doc """
  Defines a storage bucket.

  ## Examples

      storage_bucket "avatars" do
        public true
        file_size_limit "1MB"
        allowed_mime_types ["image/jpeg", "image/png"]
        
        policy :select, "Avatar images are publicly readable" do
          "true"
        end
      end
  """
  defmacro storage_bucket(name, opts \\ [], do: block) do
    quote do
      @current_storage_bucket %{
        name: unquote(name),
        policies: [],
        options: unquote(opts)
      }
      
      unquote(block)
      
      @storage_buckets @current_storage_bucket
      @current_storage_bucket nil
    end
  end

  @doc """
  Sets the storage bucket as public or private.
  """
  defmacro public(value) do
    quote do
      unless @current_storage_bucket do
        raise "public/1 can only be used inside a storage_bucket/2 block"
      end

      @current_storage_bucket Map.update!(@current_storage_bucket, :options, &Keyword.put(&1, :public, unquote(value)))
    end
  end

  @doc """
  Sets the file size limit for the storage bucket.
  """
  defmacro file_size_limit(limit) do
    quote do
      unless @current_storage_bucket do
        raise "file_size_limit/1 can only be used inside a storage_bucket/2 block"
      end

      @current_storage_bucket Map.update!(@current_storage_bucket, :options, &Keyword.put(&1, :file_size_limit, unquote(limit)))
    end
  end

  @doc """
  Sets the allowed MIME types for the storage bucket.
  """
  defmacro allowed_mime_types(types) do
    quote do
      unless @current_storage_bucket do
        raise "allowed_mime_types/1 can only be used inside a storage_bucket/2 block"
      end

      @current_storage_bucket Map.update!(@current_storage_bucket, :options, &Keyword.put(&1, :allowed_mime_types, unquote(types)))
    end
  end

  @doc """
  Compile-time callback to finalize schema definitions.
  """
  defmacro __before_compile__(_env) do
    quote do
      def __tables__, do: Enum.reverse(@tables)
      def __functions__, do: Enum.reverse(@functions)  
      def __views__, do: Enum.reverse(@views)
      def __storage_buckets__, do: Enum.reverse(@storage_buckets)
      def __custom_types__, do: Enum.reverse(@custom_types)

      def __schema__ do
        %{
          tables: __tables__(),
          functions: __functions__(),
          views: __views__(),
          storage_buckets: __storage_buckets__(),
          custom_types: __custom_types__()
        }
      end
    end
  end
end