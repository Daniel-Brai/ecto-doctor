defmodule EctoDoctor.Checks.UnindexedForeignKey do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Check
  alias EctoDoctor.Schema

  @impl EctoDoctor.Check
  def id, do: :unindexed_foreign_key

  @impl EctoDoctor.Check
  def explain do
    """
    A belongs_to column with no index that starts with it.

    Joins and preloads on it scan the table.
    Deleting a parent row scans it too to check the foreign key.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    indexed = Enum.map(table.indexes, &List.first(&1.columns))

    schema.associations
    |> Enum.filter(&(&1.kind == :belongs_to))
    |> Enum.map(&Schema.column(schema, &1.owner_key))
    |> Enum.filter(&Map.has_key?(table.columns, &1))
    |> Enum.reject(&(&1 in indexed))
    |> Enum.map(&finding(model, schema, table, &1))
  end

  defp finding(model, schema, table, column) do
    {table_arg, options} = Check.index_args(model, table)
    index = "create index(#{table_arg}, #{Check.migration_names([column])}#{options})"

    Check.finding(model, schema,
      check: id(),
      level: :warning,
      columns: [column],
      message: "#{column} is a foreign key with no index.",
      migration: [{:concurrent, index}]
    )
  end
end
