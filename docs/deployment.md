# Deployment Guide

Guide to deploying your Tenjin application to production with Supabase.

## Supabase Cloud Deployment

### 1. Create Supabase Project
```bash
# Create new project on supabase.com
# Or use CLI
supabase projects create my-production-app
```

### 2. Link Local Project
```bash
# Link your local project to the cloud project
supabase link --project-ref your-project-ref
```

### 3. Deploy Database Schema
```bash
# Push your migrations to production
supabase db push

# Verify deployment
supabase db remote commit
```

### 4. Set Up Environment Variables
```bash
# Get your production credentials
supabase status

# Set in your application environment
export SUPABASE_URL="https://your-project.supabase.co"
export SUPABASE_ANON_KEY="your-anon-key"
export SUPABASE_SERVICE_ROLE_KEY="your-service-key"
```

## Production Configuration

### Database Connection
```elixir
# config/prod.exs
config :my_app, MyApp.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true,
  socket_options: [:inet6]
```

### Supabase Client Configuration
```elixir
# config/prod.exs
config :my_app,
  supabase_url: System.get_env("SUPABASE_URL"),
  supabase_anon_key: System.get_env("SUPABASE_ANON_KEY"),
  supabase_service_key: System.get_env("SUPABASE_SERVICE_ROLE_KEY")
```

## Application Deployment

### Elixir Release
```bash
# Build production release
MIX_ENV=prod mix release

# Deploy to your hosting platform
# (Fly.io, Railway, etc.)
```

### Docker Deployment
```dockerfile
# Dockerfile
FROM elixir:1.17-alpine AS build

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY . .
RUN MIX_ENV=prod mix compile
RUN MIX_ENV=prod mix release

FROM alpine:3.18
RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app
COPY --from=build /app/_build/prod/rel/my_app .

CMD ["./bin/my_app", "start"]
```

## Migration Strategy

### Safe Migrations
1. **Always Backup** before production migrations
2. **Test in Staging** environment first
3. **Use Supabase Dashboard** to monitor during deployment
4. **Plan Rollback Strategy** for each migration

### Zero-Downtime Migrations
```sql
-- Add new columns (safe)
ALTER TABLE users ADD COLUMN phone_number TEXT;

-- Add indexes concurrently (safe)
CREATE INDEX CONCURRENTLY idx_users_phone ON users(phone_number);

-- Drop columns in separate migration after code deployment
-- ALTER TABLE users DROP COLUMN old_column;  -- Later migration
```

### Migration Checklist
- [ ] Backup database
- [ ] Test migration in staging
- [ ] Monitor application metrics
- [ ] Verify RLS policies work correctly
- [ ] Check performance impact
- [ ] Have rollback plan ready

## Monitoring and Observability

### Supabase Monitoring
- Use Supabase Dashboard for real-time metrics
- Monitor database performance and queries
- Set up alerts for error rates and response times

### Application Monitoring
```elixir
# Add telemetry for database operations
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Database metrics
      summary("my_app.repo.query.total_time", unit: {:native, :millisecond}),
      counter("my_app.repo.query.count"),
      
      # RLS policy metrics
      counter("my_app.rls.policy_violations"),
      
      # Migration metrics
      counter("my_app.migrations.applied")
    ]
  end

  defp periodic_measurements do
    []
  end
end
```

## Security Best Practices

### Environment Secrets
- Never commit credentials to version control
- Use environment variables or secret management
- Rotate keys regularly
- Use least-privilege service keys

### RLS Verification
```bash
# Test RLS policies in production
supabase db remote --db-url="postgresql://..." --execute "
  SELECT * FROM posts;  -- Should respect RLS
"
```

### Backup Strategy
```bash
# Schedule regular backups
supabase db dump --db-url="postgresql://..." --file="backup-$(date +%Y%m%d).sql"

# Test restore process
supabase db reset --db-url="postgresql://test-db" --with-seed
supabase db restore --db-url="postgresql://test-db" --file="backup.sql"
```

## Performance Optimization

### Database Optimization
- Monitor slow queries in Supabase Dashboard
- Add appropriate indexes for your RLS policies
- Use connection pooling
- Optimize large migrations

### Application Optimization
- Use prepared statements
- Implement query result caching
- Monitor memory usage
- Profile database connection usage

## Troubleshooting

### Common Issues
1. **RLS Policy Errors** - Test policies thoroughly in staging
2. **Migration Timeouts** - Break large migrations into smaller chunks
3. **Connection Limits** - Monitor and adjust pool sizes
4. **Performance Degradation** - Check for missing indexes on new queries

### Debug Tools
```bash
# Check migration status
supabase migration list

# Inspect database schema
supabase db inspect

# View real-time logs
supabase logs

# Check RLS policies
supabase db remote --execute "\\dp+ tablename"
```

## Rollback Procedures

### Emergency Rollback
1. **Identify the Issue** - Check logs and metrics
2. **Stop Traffic** - if necessary, temporarily disable features
3. **Rollback Database** - restore from backup if needed
4. **Rollback Application** - deploy previous version
5. **Verify System** - ensure everything works correctly
6. **Post-Mortem** - analyze what went wrong

### Planned Rollback
```bash
# Rollback last migration
supabase migration down

# Rollback to specific migration
supabase migration down --to 20240101120000
```