# Blog Example - Tenjin Framework

This example demonstrates how to build a simple blog application using Tenjin and Supabase.

## Features

- User authentication and profiles
- Blog posts with authors
- Comments with nested replies
- Row Level Security (RLS) for data access
- File storage for user avatars and post images

## Schema Overview

The blog application includes these main entities:

- **Users** - User accounts with authentication
- **Posts** - Blog posts with title, content, and publish status
- **Comments** - Comments on posts with support for replies
- **Storage** - File storage for avatars and post images

## Running the Example

1. **Create the project:**
   ```bash
   nix run .#tenjin new blog_example --path examples/blog_app
   cd examples/blog_app
   ```

2. **Start Supabase:**
   ```bash
   nix run .#tenjin start
   ```

3. **Generate and apply the initial migration:**
   ```bash
   nix run .#tenjin generate initial_schema
   nix run .#tenjin migrate
   ```

4. **Open Supabase Studio:**
   Visit http://localhost:54323 to explore your database

## Schema Definition

The complete schema is defined in `lib/blog_example/schema.ex`:

```elixir
defmodule BlogExample.Schema do
  use Tenjin.Schema

  # Users table with authentication integration
  table "users" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :email, :text, unique: true, null: false
    field :name, :text
    field :avatar_url, :text
    field :bio, :text
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
    
    trigger :update_updated_at, on: :update do
      "updated_at = now()"
    end
    
    has_many :posts, foreign_key: :author_id
    has_many :comments, foreign_key: :user_id
  end

  # Blog posts
  table "posts" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :title, :text, null: false
    field :slug, :text, unique: true
    field :excerpt, :text
    field :content, :text
    field :featured_image_url, :text
    field :author_id, :uuid, references: "users(id)", on_delete: :cascade
    field :published, :boolean, default: false
    field :published_at, :timestamptz
    field :created_at, :timestamptz, default: "now()"
    field :updated_at, :timestamptz, default: "now()"
    
    enable_rls()
    
    policy :select, "Published posts are publicly readable" do
      "published = true"
    end
    
    policy :select, "Authors can see their own posts", for: :authenticated do
      "auth.uid() = author_id"
    end
    
    policy :insert, "Authenticated users can create posts" do
      "auth.uid() IS NOT NULL AND auth.uid() = author_id"
    end
    
    policy :update, "Authors can edit their own posts" do
      "auth.uid() = author_id"
    end
    
    policy :delete, "Authors can delete their own posts" do
      "auth.uid() = author_id"
    end
    
    belongs_to :author, "users"
    has_many :comments, foreign_key: :post_id
    
    index [:slug], unique: true
    index [:author_id]
    index [:published, :published_at]
    index [:created_at]
    
    trigger :update_updated_at, on: :update do
      "updated_at = now()"
    end
    
    trigger :set_published_at, on: [:insert, :update] do
      """
      IF NEW.published = true AND OLD.published IS DISTINCT FROM true THEN
        NEW.published_at = now();
      END IF;
      """
    end
    
    trigger :generate_slug, on: [:insert, :update] do
      """
      IF NEW.slug IS NULL OR NEW.slug = '' THEN
        NEW.slug = slugify(NEW.title);
      END IF;
      """
    end
  end

  # Comments with nested replies
  table "comments" do
    field :id, :uuid, primary_key: true, default: "gen_random_uuid()"
    field :content, :text, null: false
    field :user_id, :uuid, references: "users(id)", on_delete: :cascade
    field :post_id, :uuid, references: "posts(id)", on_delete: :cascade
    field :parent_id, :uuid, references: "comments(id)", on_delete: :cascade
    field :created_at, :timestamptz, default: "now()"
    field :updated_at, :timestamptz, default: "now()"
    
    enable_rls()
    
    policy :select, "Comments on published posts are publicly readable" do
      """
      EXISTS(
        SELECT 1 FROM posts 
        WHERE posts.id = post_id 
        AND posts.published = true
      )
      """
    end
    
    policy :insert, "Authenticated users can comment on published posts" do
      """
      auth.uid() IS NOT NULL 
      AND auth.uid() = user_id
      AND EXISTS(
        SELECT 1 FROM posts 
        WHERE posts.id = post_id 
        AND posts.published = true
      )
      """
    end
    
    policy :update, "Users can edit their own comments within 1 hour" do
      """
      auth.uid() = user_id 
      AND created_at > now() - interval '1 hour'
      """
    end
    
    policy :delete, "Users can delete their own comments" do
      "auth.uid() = user_id"
    end
    
    belongs_to :user, "users"
    belongs_to :post, "posts"
    belongs_to :parent, "comments", optional: true
    has_many :replies, foreign_key: :parent_id, references: :id
    
    index [:post_id]
    index [:user_id]  
    index [:parent_id]
    index [:created_at]
    
    trigger :update_updated_at, on: :update do
      "updated_at = now()"
    end
  end

  # Database functions
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

  function "get_post_comment_count", [:uuid], :bigint do
    """
    RETURN (
      SELECT COUNT(*) 
      FROM comments 
      WHERE post_id = $1
    );
    """
  end

  # Database views
  view "published_posts_with_authors" do
    """
    SELECT 
      p.id,
      p.title,
      p.slug,
      p.excerpt,
      p.content,
      p.featured_image_url,
      p.published_at,
      p.created_at,
      p.updated_at,
      u.name as author_name,
      u.avatar_url as author_avatar_url,
      get_post_comment_count(p.id) as comment_count
    FROM posts p
    JOIN users u ON p.author_id = u.id
    WHERE p.published = true
    ORDER BY p.published_at DESC
    """
  end

  view "recent_comments" do
    """
    SELECT 
      c.id,
      c.content,
      c.created_at,
      u.name as user_name,
      u.avatar_url as user_avatar_url,
      p.title as post_title,
      p.slug as post_slug
    FROM comments c
    JOIN users u ON c.user_id = u.id
    JOIN posts p ON c.post_id = p.id
    WHERE p.published = true
    ORDER BY c.created_at DESC
    LIMIT 10
    """
  end

  # Storage buckets
  storage_bucket "avatars" do
    public true
    file_size_limit "2MB"
    allowed_mime_types ["image/jpeg", "image/png", "image/webp"]
    
    policy :select, "Avatar images are publicly readable" do
      "true"
    end
    
    policy :insert, "Users can upload their own avatar" do
      "auth.uid()::text = (storage.foldername(name))[1]"
    end
    
    policy :update, "Users can update their own avatar" do
      "auth.uid()::text = (storage.foldername(name))[1]"
    end
    
    policy :delete, "Users can delete their own avatar" do
      "auth.uid()::text = (storage.foldername(name))[1]"
    end
  end

  storage_bucket "post_images" do
    public true
    file_size_limit "5MB"
    allowed_mime_types ["image/jpeg", "image/png", "image/webp", "image/gif"]
    
    policy :select, "Post images are publicly readable" do
      "true"
    end
    
    policy :insert, "Authors can upload images for their posts" do
      """
      auth.uid() IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM posts 
        WHERE posts.id::text = (storage.foldername(name))[1] 
        AND posts.author_id = auth.uid()
      )
      """
    end
    
    policy :update, "Authors can update their post images" do
      """
      auth.uid() IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM posts 
        WHERE posts.id::text = (storage.foldername(name))[1] 
        AND posts.author_id = auth.uid()
      )
      """
    end
    
    policy :delete, "Authors can delete their post images" do
      """
      auth.uid() IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM posts 
        WHERE posts.id::text = (storage.foldername(name))[1] 
        AND posts.author_id = auth.uid()
      )
      """
    end
  end
end
```

## Key Features Demonstrated

1. **Row Level Security**: Comprehensive RLS policies for multi-tenant data access
2. **Relationships**: Foreign keys and relationship definitions between tables
3. **Triggers**: Automatic timestamp updates and slug generation
4. **Functions**: Custom database functions for common operations
5. **Views**: Materialized views for complex queries
6. **Storage**: File storage with access policies
7. **Indexes**: Performance optimization with strategic indexing

## Next Steps

- Add seed data in `priv/seeds/dev.exs`
- Build a frontend using your preferred framework
- Deploy to Supabase Cloud when ready for production
- Extend the schema with additional features like tags, categories, or user roles
