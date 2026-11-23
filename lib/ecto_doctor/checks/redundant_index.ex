defmodule EctoDoctor.Checks.RedundantIndex do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Check
  alias EctoDoctor.Finding

  @impl EctoDoctor.Check
  def id, do: :redundant_index

  @impl EctoDoctor.Check
  def explain do
    """
    An index whose columns another index already starts with.

    The other index serves every query this one does.
    Keeping both slows every write and takes space.
    A unique index is only redundant next to another unique index on the same columns.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model.database.tables
    |> Map.values()
    |> Enum.flat_map(&check_table(model, &1))
  end

  defp check_table(model, table) do
    indexes = Enum.reject(table.indexes, &(&1.partial? or &1.expression?))

    for index <- indexes, covered?(index, indexes), do: finding(model, table, index)
  end

  defp covered?(index, indexes), do: Enum.any?(indexes, &covers?(&1, index))

  # Comparing names keeps two identical indexes from both being reported
  # A GIN index and a btree index answer different queries so only the same method can cover
  defp covers?(other, index) do
    cond do
      other.name == index.name or index.primary? or other.method != index.method -> false
      other.columns == index.columns and other.unique? == index.unique? -> other.name < index.name
      index.unique? -> false
      true -> List.starts_with?(other.columns, index.columns)
    end
  end

  defp finding(model, table, index) do
    table_name = Check.table_name(model, table)
    {table_arg, options} = Check.index_args(model, table)
    drop = "drop index(#{table_arg}, [], name: #{Check.literal(index.name)}#{options})"

    %Finding{
      check: id(),
      level: :info,
      table: table_name,
      columns: index.columns,
      message: "Another index on #{table_name} already covers #{index.name}.",
      migration: [{:concurrent, drop}]
    }
  end
end
