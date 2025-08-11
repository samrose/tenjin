# Row Level Security (RLS) Policies

Guide to implementing secure database access with Tenjin's RLS support.

## What is Row Level Security?

Row Level Security (RLS) enables fine-grained access control at the database level. Instead of managing permissions in application code, RLS policies are enforced by PostgreSQL itself.

## Enabling RLS

```elixir
table "posts" do
  # fields...
  
  enable_rls()  # Enable RLS for this table
  
  # policies...
end
```

## Policy Types

### SELECT Policies (Read Access)
```elixir
# Public read access
policy :select, "Published posts are public" do
  "published = true"
end

# User-specific access
policy :select, "Users can view their own posts" do
  "auth.uid() = author_id"
end
```

### INSERT Policies (Create Access)
```elixir
# Authenticated users only
policy :insert, "Authenticated users can create posts" do
  "auth.uid() = author_id"
end
```

### UPDATE Policies (Modify Access)
```elixir
# Owners only
policy :update, "Authors can update their posts" do
  "auth.uid() = author_id"
end
```

### DELETE Policies (Delete Access)
```elixir
# Owners only
policy :delete, "Authors can delete their posts" do
  "auth.uid() = author_id"
end
```

## Common Patterns

### User Ownership
```elixir
policy :all, "Users own their records" do
  "auth.uid() = user_id"
end
```

### Public Read, Owner Write
```elixir
policy :select, "Public read access" do
  "true"
end

policy :insert, "Authenticated users can create" do
  "auth.uid() IS NOT NULL"
end

policy :update, "Owners can update" do
  "auth.uid() = created_by"
end
```

### Complex Visibility Rules
```elixir
policy :select, "Complex visibility rules" do
  """
  published = true OR 
  auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM collaborators WHERE post_id = id AND user_id = auth.uid())
  """
end
```

## Supabase Auth Integration

Tenjin policies integrate seamlessly with Supabase Auth:

- `auth.uid()` - Current authenticated user ID
- `auth.role()` - Current user role
- `auth.jwt()` - Access to JWT claims

## Testing RLS Policies

Always test your RLS policies thoroughly:

1. Test as unauthenticated user
2. Test as different authenticated users
3. Test edge cases and boundary conditions
4. Use Supabase's built-in policy testing tools

## Best Practices

1. **Start Restrictive** - Begin with minimal access, expand as needed
2. **Test Thoroughly** - RLS policies are security-critical
3. **Document Clearly** - Use descriptive policy names and comments
4. **Keep It Simple** - Complex policies are harder to audit and debug
5. **Use Indexes** - Ensure policy conditions can use appropriate indexes