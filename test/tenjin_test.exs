defmodule TenjinTest do
  use ExUnit.Case
  doctest Tenjin

  test "version returns current version" do
    assert is_binary(Tenjin.version())
    assert String.match?(Tenjin.version(), ~r/^\d+\.\d+\.\d+/)
  end

  test "config returns application configuration" do
    config = Tenjin.config()
    assert is_list(config)
  end

  test "supabase_dir returns configured directory" do
    assert Tenjin.supabase_dir() == "supabase"
  end

  test "migrations_dir returns correct path" do
    assert Tenjin.migrations_dir() == "supabase/migrations"
  end

  test "schema_modules returns configured modules" do
    modules = Tenjin.schema_modules()
    assert is_list(modules)
  end
end
