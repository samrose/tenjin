defmodule BlogExample.Schema do
  @moduledoc """
  Complete blog schema example using Tenjin DSL.
  
  This example demonstrates a full-featured blog with:
  - User management and authentication
  - Post creation, editing, and publishing
  - Category system with many-to-many relationships
  - Comment system
  - Comprehensive Row Level Security policies
  - Proper indexing for performance
  """

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