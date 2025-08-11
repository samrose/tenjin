defmodule Tenjin.Types do
  @moduledoc """
  Type definitions and utilities for Tenjin framework.
  """

  @type table_name :: String.t()
  @type field_name :: atom()
  @type field_type :: atom()
  @type sql_statement :: String.t()

  @type table_definition :: %{
    name: table_name(),
    fields: [field_definition()],
    indexes: [index_definition()],
    policies: [policy_definition()],
    triggers: [trigger_definition()],
    relationships: [relationship_definition()],
    rls_enabled: boolean(),
    options: keyword()
  }

  @type field_definition :: %{
    name: field_name(),
    type: field_type(),
    options: keyword()
  }

  @type index_definition :: %{
    fields: [field_name()],
    options: keyword()
  }

  @type policy_definition :: %{
    action: atom(),
    description: String.t(),
    condition: String.t(),
    options: keyword()
  }

  @type trigger_definition :: %{
    name: atom(),
    events: [atom()],
    body: String.t(),
    options: keyword()
  }

  @type relationship_definition :: %{
    type: :belongs_to | :has_many | :has_one,
    name: atom(),
    table: table_name(),
    options: keyword()
  }

  @type function_definition :: %{
    name: String.t(),
    args: [field_type()],
    return_type: String.t(),
    body: String.t(),
    options: keyword()
  }

  @type view_definition :: %{
    name: String.t(),
    query: String.t(),
    options: keyword()
  }

  @type storage_bucket_definition :: %{
    name: String.t(),
    policies: [policy_definition()],
    options: keyword()
  }

  @doc """
  PostgreSQL data types supported by Tenjin.
  """
  @postgresql_types [
    # Numeric types
    :smallint, :integer, :bigint, :decimal, :numeric, :real, :double_precision,
    :smallserial, :serial, :bigserial,
    
    # Monetary types
    :money,
    
    # Character types
    :varchar, :char, :text,
    
    # Binary types
    :bytea,
    
    # Date/time types
    :timestamp, :timestamptz, :date, :time, :timetz, :interval,
    
    # Boolean type
    :boolean,
    
    # Enumerated types
    :enum,
    
    # Geometric types
    :point, :line, :lseg, :box, :path, :polygon, :circle,
    
    # Network address types
    :cidr, :inet, :macaddr, :macaddr8,
    
    # Bit string types
    :bit, :bit_varying,
    
    # Text search types
    :tsvector, :tsquery,
    
    # UUID type
    :uuid,
    
    # XML type
    :xml,
    
    # JSON types
    :json, :jsonb,
    
    # Arrays
    :array,
    
    # Range types
    :int4range, :int8range, :numrange, :tsrange, :tstzrange, :daterange
  ]

  def postgresql_types, do: @postgresql_types

  @doc """
  Validates if a given type is supported.
  """
  def valid_type?(type) when type in @postgresql_types, do: true
  def valid_type?(_), do: false

  @doc """
  Converts Elixir type atoms to PostgreSQL type strings.
  """
  def to_sql_type(:string), do: "text"
  def to_sql_type(:text), do: "text"
  def to_sql_type(:integer), do: "integer"
  def to_sql_type(:bigint), do: "bigint"
  def to_sql_type(:float), do: "real"
  def to_sql_type(:decimal), do: "decimal"
  def to_sql_type(:boolean), do: "boolean"
  def to_sql_type(:uuid), do: "uuid"
  def to_sql_type(:timestamptz), do: "timestamptz"
  def to_sql_type(:timestamp), do: "timestamp"
  def to_sql_type(:date), do: "date"
  def to_sql_type(:time), do: "time"
  def to_sql_type(:json), do: "json"
  def to_sql_type(:jsonb), do: "jsonb"
  def to_sql_type(type) when is_atom(type), do: Atom.to_string(type)
  def to_sql_type(type) when is_binary(type), do: type

  @doc """
  RLS policy actions supported by PostgreSQL.
  """
  @rls_actions [:select, :insert, :update, :delete, :all]
  def rls_actions, do: @rls_actions

  @doc """
  Validates if a given RLS action is supported.
  """
  def valid_rls_action?(action) when action in @rls_actions, do: true
  def valid_rls_action?(_), do: false

  @doc """
  Storage bucket file size limits.
  """
  def parse_file_size(size) when is_binary(size) do
    case Regex.run(~r/^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)?$/i, String.trim(size)) do
      [_, number, unit] ->
        {value, ""} = Float.parse(number)
        multiplier = case String.upcase(unit || "B") do
          "B" -> 1
          "KB" -> 1024
          "MB" -> 1024 * 1024
          "GB" -> 1024 * 1024 * 1024
          "TB" -> 1024 * 1024 * 1024 * 1024
        end
        {:ok, round(value * multiplier)}
      _ ->
        {:error, "Invalid file size format"}
    end
  end

  def parse_file_size(size) when is_integer(size), do: {:ok, size}
  def parse_file_size(_), do: {:error, "Invalid file size"}
end
