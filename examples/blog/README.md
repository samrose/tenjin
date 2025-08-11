# Blog Example

Complete blog application schema using Tenjin DSL.

## Features

- **User Management** - Registration, authentication, profiles
- **Post Management** - Create, edit, publish posts with rich content
- **Category System** - Organize posts with categories (many-to-many)
- **Comment System** - User comments on posts
- **Row Level Security** - Comprehensive RLS policies for all tables
- **Performance Optimized** - Proper indexes for all query patterns

## Schema Overview

### Tables
- `users` - User accounts and profiles
- `posts` - Blog posts with authorship and publishing
- `categories` - Post categories for organization
- `post_categories` - Many-to-many relationship between posts and categories
- `comments` - User comments on posts

### Key Features
- **UUID Primary Keys** - All tables use UUIDs for better scalability
- **Timestamp Tracking** - Created/updated timestamps on all relevant tables
- **Cascade Deletes** - Proper foreign key relationships with cascade deletes
- **Unique Constraints** - Email uniqueness, slug uniqueness, etc.
- **RLS Security** - Complete Row Level Security implementation

## Usage

1. **Copy the schema** to your Tenjin project:
   ```elixir
   # Copy contents to lib/my_app/schema.ex
   ```

2. **Generate migration**:
   ```bash
   mix tenjin.gen.migration blog_schema
   ```

3. **Apply to database**:
   ```bash
   mix tenjin.migrate --local
   ```

## RLS Policies

### Users Table
- Users can view and update their own profiles only

### Posts Table
- **Public Read** - Published posts are viewable by everyone
- **Author Read** - Authors can view their own unpublished posts
- **Author Write** - Authors can create, update, delete their own posts

### Categories Table
- **Public Read** - Categories are publicly viewable
- No write policies (managed by admins through direct SQL)

### Post Categories Table
- **Follows Post Visibility** - Categories are visible based on post visibility
- **Author Management** - Authors can manage categories for their own posts

### Comments Table
- **Public Read** - Comments are visible on published posts
- **Author Write** - Users can create, update, delete their own comments

## Query Examples

### Get Published Posts with Authors
```sql
SELECT 
  p.id, p.title, p.slug, p.excerpt, p.published_at,
  u.name as author_name, u.avatar_url as author_avatar
FROM posts p
JOIN users u ON p.author_id = u.id
WHERE p.published = true
ORDER BY p.published_at DESC;
```

### Get Post with Categories
```sql
SELECT 
  p.*,
  array_agg(c.name) as categories
FROM posts p
LEFT JOIN post_categories pc ON p.id = pc.post_id
LEFT JOIN categories c ON pc.category_id = c.id
WHERE p.id = $1
GROUP BY p.id;
```

### Get Comments for Post
```sql
SELECT 
  c.*,
  u.name as author_name,
  u.avatar_url as author_avatar
FROM comments c
JOIN users u ON c.author_id = u.id
WHERE c.post_id = $1
ORDER BY c.created_at ASC;
```

## Best Practices Demonstrated

1. **Comprehensive RLS** - Every table has appropriate security policies
2. **Proper Indexing** - Indexes on all foreign keys and query patterns
3. **Data Integrity** - Foreign key constraints with appropriate cascade rules
4. **Scalable Design** - UUID keys and proper normalization
5. **Security First** - RLS policies prevent unauthorized access at database level