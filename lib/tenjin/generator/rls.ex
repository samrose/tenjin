defmodule Tenjin.Generator.RLS do
  @moduledoc """
  Row Level Security (RLS) policy generation from Tenjin schema definitions.
  
  This module generates PostgreSQL RLS policies from Tenjin policy definitions.
  """


  @doc """
  Generates RLS policies for a table.
  """
  def generate_policies(%{name: table_name, policies: policies, rls_enabled: true}) do
    policies
    |> Enum.reverse()
    |> Enum.map(&generate_policy(table_name, &1))
    |> Enum.join("\n")
  end

  def generate_policies(%{rls_enabled: false}), do: ""
  def generate_policies(%{policies: []}), do: ""

  @doc """
  Generates a single RLS policy.
  """
  def generate_policy(table_name, %{action: action, description: description, condition: condition, options: opts}) do
    policy_name = opts[:name] || generate_policy_name(table_name, action, description)
    
    action_sql = format_action(action)
    role_clause = format_role_clause(opts[:for])
    {using_clause, with_check_clause} = format_policy_clauses(action, condition, opts)

    comment_sql = """
    COMMENT ON POLICY #{policy_name} ON #{table_name} IS #{escape_string(description)};
    """

    policy_sql = """
    CREATE POLICY #{policy_name} ON #{table_name}
      FOR #{action_sql}#{role_clause}#{using_clause}#{with_check_clause};
    """

    policy_sql <> comment_sql
  end

  defp generate_policy_name(table_name, action, description) do
    # Generate a policy name from table, action, and sanitized description
    sanitized_desc = 
      description
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s]/, "")
      |> String.split()
      |> Enum.take(3)
      |> Enum.join("_")

    "#{table_name}_#{action}_#{sanitized_desc}"
  end

  defp format_action(:all), do: "ALL"
  defp format_action(action), do: String.upcase(to_string(action))

  defp format_role_clause(nil), do: ""
  defp format_role_clause(:all), do: ""
  defp format_role_clause(:authenticated), do: "\n  TO authenticated"
  defp format_role_clause(:anon), do: "\n  TO anon"  
  defp format_role_clause(role) when is_binary(role), do: "\n  TO #{role}"
  defp format_role_clause(roles) when is_list(roles) do
    roles_str = Enum.join(roles, ", ")
    "\n  TO #{roles_str}"
  end

  defp format_policy_clauses(action, condition, opts) do
    case action do
      :insert ->
        # INSERT policies only use WITH CHECK
        using_clause = ""
        with_check_clause = "\n  WITH CHECK (#{condition})"
        {using_clause, with_check_clause}
        
      :select ->
        # SELECT policies only use USING
        using_clause = "\n  USING (#{condition})"
        with_check_clause = ""
        {using_clause, with_check_clause}
        
      :update ->
        # UPDATE policies can use both USING and WITH CHECK
        using_clause = "\n  USING (#{condition})"
        with_check_clause = case opts[:with_check] do
          nil -> ""
          check_condition -> "\n  WITH CHECK (#{check_condition})"
        end
        {using_clause, with_check_clause}
        
      :delete ->
        # DELETE policies only use USING
        using_clause = "\n  USING (#{condition})"
        with_check_clause = ""
        {using_clause, with_check_clause}
        
      :all ->
        # ALL policies use both USING and WITH CHECK
        using_clause = "\n  USING (#{condition})"
        with_check_clause = "\n  WITH CHECK (#{condition})"
        {using_clause, with_check_clause}
    end
  end

  @doc """
  Generates policy for storage buckets.
  """
  def generate_storage_policy(bucket_name, %{action: action, description: description, condition: condition, options: opts}) do
    policy_name = opts[:name] || "#{bucket_name}_#{action}_policy"
    
    action_sql = format_storage_action(action)
    role_clause = format_role_clause(opts[:for])

    comment_sql = """
    COMMENT ON POLICY #{policy_name} ON storage.objects IS #{escape_string(description)};
    """

    policy_sql = """
    CREATE POLICY #{policy_name} ON storage.objects
      FOR #{action_sql}#{role_clause}
      USING (bucket_id = '#{bucket_name}' AND #{condition});
    """

    policy_sql <> comment_sql
  end

  defp format_storage_action(:select), do: "SELECT"
  defp format_storage_action(:insert), do: "INSERT"
  defp format_storage_action(:update), do: "UPDATE"
  defp format_storage_action(:delete), do: "DELETE"
  defp format_storage_action(:all), do: "ALL"

  @doc """
  Generates policy drop statements.
  """
  def drop_policy(table_name, policy_name) do
    "DROP POLICY IF EXISTS #{policy_name} ON #{table_name};"
  end

  def drop_storage_policy(policy_name) do
    "DROP POLICY IF EXISTS #{policy_name} ON storage.objects;"
  end

  @doc """
  Generates policy changes between old and new definitions.
  """
  def generate_policy_changes(table_name, old_policies, new_policies) do
    old_policy_names = Enum.map(old_policies, &policy_name/1)
    new_policy_names = Enum.map(new_policies, &policy_name/1)

    # Policies to drop (in old but not in new)
    drop_statements = 
      old_policy_names
      |> Enum.reject(&(&1 in new_policy_names))
      |> Enum.map(&drop_policy(table_name, &1))

    # Policies to create (in new but not in old, or changed)
    create_statements = 
      new_policies
      |> Enum.filter(fn policy ->
        name = policy_name(policy)
        old_policy = Enum.find(old_policies, &(policy_name(&1) == name))
        
        # Create if new or if definition changed
        old_policy == nil or policies_different?(old_policy, policy)
      end)
      |> Enum.map(&generate_policy(table_name, &1))

    # If we're recreating a policy, drop it first
    recreate_drops = 
      new_policies
      |> Enum.filter(fn policy ->
        name = policy_name(policy)
        old_policy = Enum.find(old_policies, &(policy_name(&1) == name))
        old_policy != nil and policies_different?(old_policy, policy)
      end)
      |> Enum.map(&drop_policy(table_name, policy_name(&1)))

    (drop_statements ++ recreate_drops ++ create_statements)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp policy_name(%{options: opts} = policy) do
    opts[:name] || generate_policy_name("", policy.action, policy.description)
  end

  defp policies_different?(old_policy, new_policy) do
    # Compare relevant fields to determine if policies are different
    old_key = {old_policy.action, old_policy.condition, old_policy.options}
    new_key = {new_policy.action, new_policy.condition, new_policy.options}
    old_key != new_key
  end

  @doc """
  Generates RLS policy templates for common patterns.
  """
  def user_owns_record_policy(_table_name, user_id_field \\ :user_id) do
    %{
      action: :all,
      description: "Users can only access their own records",
      condition: "auth.uid() = #{user_id_field}",
      options: []
    }
  end

  def public_read_policy() do
    %{
      action: :select,
      description: "Public read access",
      condition: "true",
      options: []
    }
  end

  def authenticated_only_policy(actions \\ [:insert, :update, :delete]) do
    actions
    |> List.wrap()
    |> Enum.map(fn action ->
      %{
        action: action,
        description: "Authenticated users only",
        condition: "auth.uid() IS NOT NULL",
        options: []
      }
    end)
  end

  def owner_or_public_read_policy(owner_field, published_field \\ :published) do
    [
      %{
        action: :select,
        description: "Public can read published records",
        condition: "#{published_field} = true",
        options: []
      },
      %{
        action: :select,
        description: "Owners can read their own records",
        condition: "auth.uid() = #{owner_field}",
        options: [for: :authenticated]
      }
    ]
  end

  defp escape_string(str) do
    "'#{String.replace(str, "'", "''")}'"
  end
end
