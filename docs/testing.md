# Testing Guide

Guide to testing your Tenjin schemas and database logic.

## Testing Strategy

### Schema Validation Tests
Test that your schema definitions generate correct SQL:

```elixir
defmodule MyApp.SchemaTest do
  use ExUnit.Case

  test "schema compiles without errors" do
    assert MyApp.Schema.__schema__()
  end

  test "generates correct table structure" do
    schema = MyApp.Schema.__schema__()
    users_table = Enum.find(schema.tables, &(&1.name == "users"))
    
    assert users_table
    assert Enum.any?(users_table.fields, &(&1.name == :email))
  end
end
```

### Migration Tests
Test that migrations apply cleanly:

```bash
# Test migration generation
mix tenjin.gen.migration test_schema

# Test migration application
supabase db reset
mix tenjin.migrate --local
```

### RLS Policy Tests
Test Row Level Security policies with different user contexts:

```elixir
# In your test suite
test "users can only see their own posts" do
  # Create test data
  user1 = create_user()
  user2 = create_user()
  
  post1 = create_post(author: user1)
  post2 = create_post(author: user2)
  
  # Test as user1
  with_user(user1) do
    posts = fetch_posts()
    assert Enum.member?(posts, post1)
    refute Enum.member?(posts, post2)
  end
end
```

## Test Database Setup

### Local Testing with Supabase
```bash
# Start test database
supabase start

# Apply schema
mix tenjin.migrate --local

# Run tests
mix test
```

### Test Configuration
```elixir
# config/test.exs
config :my_app,
  database_url: "postgresql://postgres:postgres@localhost:54322/postgres",
  supabase_url: "http://localhost:54321",
  supabase_anon_key: "your-anon-key"
```

## Testing Patterns

### Database Transactions
Wrap tests in transactions for isolation:

```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
  
  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, {:shared, self()})
  end
  
  :ok
end
```

### Factory Pattern
Create test data factories:

```elixir
defmodule MyApp.Factory do
  def build(:user) do
    %{
      email: "user#{System.unique_integer()}@example.com",
      name: "Test User"
    }
  end
  
  def create(factory) do
    factory
    |> build()
    |> MyApp.Repo.insert!()
  end
end
```

### RLS Context Testing
Test policies under different authentication contexts:

```elixir
defmodule MyApp.TestHelpers do
  def with_user(user, fun) do
    # Set auth context for RLS policies
    Postgrex.query!(MyApp.Repo, "SELECT set_config('request.jwt.claims', $1, true)", [
      Jason.encode!(%{"sub" => user.id})
    ])
    
    fun.()
    
    # Clear auth context
    Postgrex.query!(MyApp.Repo, "SELECT set_config('request.jwt.claims', '', true)", [])
  end
  
  def without_auth(fun) do
    Postgrex.query!(MyApp.Repo, "SELECT set_config('request.jwt.claims', '', true)", [])
    fun.()
  end
end
```

## Integration Tests

### Full Workflow Testing
```elixir
test "complete blog workflow" do
  # 1. Start with empty database
  supabase_reset()
  
  # 2. Apply migrations
  assert {:ok, _} = apply_migrations()
  
  # 3. Test user registration
  user = create_user(email: "author@blog.com")
  
  # 4. Test post creation
  with_user(user) do
    post = create_post(title: "My First Post", published: true)
    assert post.author_id == user.id
  end
  
  # 5. Test public access
  without_auth do
    posts = list_published_posts()
    assert length(posts) == 1
  end
end
```

## Continuous Integration

### GitHub Actions Example
```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v2
    
    - name: Setup Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.17'
        otp-version: '27'
    
    - name: Setup Supabase CLI
      uses: supabase/setup-cli@v1
      with:
        version: latest
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Start Supabase
      run: supabase start
    
    - name: Run migrations
      run: mix tenjin.migrate --local
    
    - name: Run tests
      run: mix test
```

## Best Practices

1. **Test Both Schema and Data** - Test schema generation AND actual data access
2. **Use Transactions** - Keep tests isolated with database transactions
3. **Test RLS Policies** - Verify security policies work as expected
4. **Mock External Services** - Mock Supabase Auth for faster tests
5. **Test Edge Cases** - Test boundary conditions and error scenarios
6. **Keep Tests Fast** - Use factories and minimal data sets
7. **Test Migrations** - Ensure migrations can be applied and rolled back safely