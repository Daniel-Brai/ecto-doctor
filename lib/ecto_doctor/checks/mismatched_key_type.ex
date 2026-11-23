defmodule EctoDoctor.Checks.MismatchedKeyType do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Check
  alias EctoDoctor.Database

  @impl EctoDoctor.Check
  def id, do: :mismatched_key_type

  @impl EctoDoctor.Check
  def explain do
    """
    A foreign key column whose type differs from the key it points to.

    An integer pointing at a bigint key works until the ids pass 2 billion.
    Then inserts fail.
    Joins across different types also skip indexes on some databases.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    table.constraints
    |> Enum.filter(&(&1.kind == :foreign_key))
    |> Enum.flat_map(&key_columns(model.database, table, &1))
    |> Enum.reject(fn {column, key} -> column.type == key.type end)
    |> Enum.map(fn {column, key} -> finding(model, schema, column, key) end)
  end

  defp key_columns(database, table, %{columns: [name], references: {prefix, key_table, [key]}}) do
    with %{} = column <- table.columns[name],
         %{} = key_table <- Database.table(database, prefix, key_table),
         %{} = key <- key_table.columns[key] do
      [{column, key}]
    else
      nil -> []
    end
  end

  # A key over several columns is left out
  defp key_columns(_database, _table, _constraint), do: []

  defp finding(model, schema, column, key) do
    Check.finding(model, schema,
      check: id(),
      level: :warning,
      columns: [column.name],
      message: "#{column.name} is #{column.type} but the key it points to is #{key.type}."
    )
  end
end
