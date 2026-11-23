defmodule EctoDoctor.Checks.OnDeleteMismatch do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Check
  alias EctoDoctor.Database
  alias EctoDoctor.Database.Constraint
  alias EctoDoctor.Database.Table
  alias EctoDoctor.Schema

  @actions %{delete_all: "CASCADE", nilify_all: "SET NULL"}

  @impl EctoDoctor.Check
  def id, do: :on_delete_mismatch

  @impl EctoDoctor.Check
  def explain do
    """
    A has_many or has_one on_delete option that disagrees with the foreign key's ON DELETE.

    Ecto's on_delete runs in your app and only when you delete through Ecto.
    The database action always runs.
    When they disagree the result depends on how the row was deleted.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    schema.associations
    |> Enum.filter(&cascading?/1)
    |> Enum.flat_map(&foreign_key(model, table, &1))
    |> Enum.reject(fn {assoc, _related_table, key} ->
      key.on_delete == Map.fetch!(@actions, assoc.on_delete)
    end)
    |> Enum.map(&finding(model, schema, &1))
  end

  defp cascading?(assoc) do
    assoc.kind in [:has_many, :has_one] and Map.has_key?(@actions, assoc.on_delete)
  end

  # The foreign key lives on the related table and points back at this one
  defp foreign_key(model, table, assoc) do
    with %Schema{} = related <- Enum.find(model.schemas, &(&1.module == assoc.related)),
         %Table{} = related_table <- related_table(model, assoc),
         column = Schema.column(related, assoc.related_key),
         %Constraint{} = key <-
           Enum.find(related_table.constraints, &points_at?(&1, column, table, model.database)) do
      [{assoc, related_table, key}]
    else
      nil -> []
    end
  end

  # An association like {"archived_reviews", Review} reads another table than the schema's own
  defp related_table(model, assoc) do
    Database.table(model.database, assoc.related_prefix, assoc.related_source)
  end

  defp points_at?(
         %Constraint{kind: :foreign_key, columns: [column]} = key,
         column,
         table,
         database
       ) do
    {prefix, name, _keys} = key.references
    {prefix || database.default_prefix, name} == {table.prefix, table.name}
  end

  defp points_at?(_constraint, _column, _table, _database), do: false

  defp finding(model, schema, {assoc, related_table, key}) do
    Check.finding(model, schema,
      check: id(),
      level: :warning,
      table: Check.table_name(model, related_table),
      columns: key.columns,
      message:
        "#{assoc.name} has on_delete: #{inspect(assoc.on_delete)} but its foreign key is ON DELETE #{key.on_delete}."
    )
  end
end
