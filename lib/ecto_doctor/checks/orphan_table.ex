defmodule EctoDoctor.Checks.OrphanTable do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Check
  alias EctoDoctor.Finding

  @impl EctoDoctor.Check
  def id, do: :orphan_table

  @impl EctoDoctor.Check
  def explain do
    """
    A table no schema points to.

    It may be left over from removed code.
    Join tables of many_to_many associations and the tables in ignore_tables are left out.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    known = known_tables(model)

    model.database.tables
    |> Map.values()
    |> Enum.reject(&MapSet.member?(known, {&1.prefix, &1.name}))
    |> Enum.map(&finding(model, &1))
  end

  defp known_tables(model) do
    model.schemas
    |> Enum.flat_map(&tables(&1, model.database.default_prefix))
    |> MapSet.new()
  end

  # Tables an association uses live in the prefix of the schema that points at them
  defp tables(schema, default_prefix) do
    prefix = schema.prefix || default_prefix

    # A join table or a table an association names itself, like {"archived_reviews", Review}
    used_tables =
      schema.associations
      |> Enum.flat_map(&[&1.join_through, &1.related_source])
      |> Enum.reject(&is_nil/1)

    Enum.map([schema.source | used_tables], &{prefix, &1})
  end

  defp finding(model, table) do
    table_name = Check.table_name(model, table)

    %Finding{
      check: id(),
      level: :info,
      table: table_name,
      message: "#{table_name} has no schema."
    }
  end
end
