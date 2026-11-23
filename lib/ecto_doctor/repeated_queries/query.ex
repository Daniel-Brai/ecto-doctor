defmodule EctoDoctor.RepeatedQueries.Query do
  @moduledoc false

  alias EctoDoctor.RepeatedQueries.Finding
  alias EctoDoctor.Schema

  @reuse "Run this query once and reuse the result instead of running it on every pass."

  @spec select?(String.t()) :: boolean()
  def select?(sql) do
    sql |> String.trim_leading() |> String.upcase() |> String.starts_with?(["SELECT", "WITH"])
  end

  @doc "Keeps the stacktrace frames that belong to the given apps."
  @spec frames(nil | list(), MapSet.t(atom()), [module()]) :: [Finding.frame()]
  def frames(nil, _apps, _ignored), do: []

  def frames(stacktrace, apps, ignored) do
    stacktrace
    |> Enum.filter(fn {module, _fun, _arity, location} ->
      app_frame?(module, apps, ignored) or test_frame?(location)
    end)
    |> Enum.map(fn {module, fun, arity, location} ->
      arity = if is_list(arity), do: length(arity), else: arity
      {module, fun, arity, to_string(location[:file]), location[:line]}
    end)
  end

  # A test module belongs to no app so its frames are kept by file
  # Two calls on different lines of a test are then told apart from a loop
  defp test_frame?(location) do
    file = location[:file]
    file != nil and String.ends_with?(to_string(file), "_test.exs")
  end

  defp app_frame?(module, apps, ignored) do
    case :application.get_application(module) do
      {:ok, app} -> MapSet.member?(apps, app) and module not in ignored
      :undefined -> false
    end
  end

  @doc """
  Suggests how to stop the query from repeating.

  It names the association to preload when exactly one association loads rows that way.
  A query that loads an association ends by matching that association's key against a single value.
  """
  @spec fix(String.t(), nil | String.t(), [Schema.t()]) :: String.t()
  def fix(_sql, nil, _schemas), do: @reuse

  def fix(sql, source, schemas) do
    case preloads(sql, source, schemas) do
      [] ->
        @reuse

      [{schema, assoc}] ->
        "Preload #{inspect(assoc.name)} on #{inspect(schema.module)} where the parent rows are loaded."

      _many ->
        "Load these #{source} rows in one query, with a preload or a where on their keys."
    end
  end

  defp preloads(sql, source, schemas) do
    for schema <- schemas, assoc <- schema.associations, loads?(assoc, sql, source) do
      {schema, assoc}
    end
  end

  defp loads?(assoc, sql, source),
    do: assoc.related_source == source and by_key?(sql, assoc.related_key)

  # PostgreSQL numbers its parameters while MySQL and SQLite use ? and MySQL quotes names with backticks
  defp by_key?(sql, key) do
    sql
    |> without_order_by()
    |> String.ends_with?([".\"#{key}\" = $1)", ".\"#{key}\" = ?)", ".`#{key}` = ?)"])
  end

  # Preloading a list appends ORDER BY on the key so only what comes before it matters
  defp without_order_by(sql) do
    case :binary.matches(sql, " ORDER BY ") do
      [] -> sql
      matches -> binary_part(sql, 0, matches |> List.last() |> elem(0))
    end
  end
end
