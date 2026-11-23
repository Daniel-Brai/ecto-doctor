defmodule EctoDoctor.Checks.MissingForeignKey do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Adapter.Postgres
  alias EctoDoctor.Check
  alias EctoDoctor.Model
  alias EctoDoctor.Schema

  @impl EctoDoctor.Check
  def id, do: :missing_foreign_key

  @impl EctoDoctor.Check
  def explain do
    """
    A belongs_to column with no foreign key constraint.

    Nothing stops a row from pointing at a parent that doesn't exist.
    Deleting the parent leaves the row behind.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    # A column inside a foreign key over several columns still points at its table
    keyed_columns =
      for %{kind: :foreign_key, columns: columns} <- table.constraints,
          column <- columns,
          do: column

    schema.associations
    |> Enum.filter(&stored_belongs_to?(&1, schema, table))
    |> Enum.reject(&(Schema.column(schema, &1.owner_key) in keyed_columns))
    |> Enum.map(&finding(model, schema, table, &1))
  end

  # A belongs_to whose column is in this table and whose related schema has a table of its own
  defp stored_belongs_to?(assoc, schema, table) do
    assoc.kind == :belongs_to and assoc.related_source != nil and
      Map.has_key?(table.columns, Schema.column(schema, assoc.owner_key))
  end

  defp finding(model, schema, table, assoc) do
    column = Schema.column(schema, assoc.owner_key)

    Check.finding(model, schema,
      check: id(),
      level: :warning,
      columns: [column],
      message: "#{column} points at #{assoc.related_source} but has no foreign key constraint.",
      migration: migration(model, table, column, assoc)
    )
  end

  # A related key with source: lives in a column named differently from the field
  defp related_column(model, assoc) do
    case Enum.find(model.schemas, &(&1.module == assoc.related)) do
      nil -> to_string(assoc.related_key)
      related -> Schema.column(related, assoc.related_key)
    end
  end

  # The constraint goes in NOT VALID so it doesn't lock both tables while it checks old rows
  defp migration(%Model{database: %{adapter: Postgres}} = model, table, column, assoc) do
    related_prefix = assoc.related_prefix || model.database.default_prefix

    table_name = Check.sql_name(table.prefix, table.name)
    related_name = Check.sql_name(related_prefix, assoc.related_source)
    constraint = Check.sql_name(nil, "#{table.name}_#{column}_fkey")
    column_name = Check.sql_name(nil, column)
    key_name = Check.sql_name(nil, related_column(model, assoc))

    add =
      "ALTER TABLE #{table_name} ADD CONSTRAINT #{constraint} FOREIGN KEY (#{column_name}) REFERENCES #{related_name} (#{key_name}) NOT VALID"

    drop = "ALTER TABLE #{table_name} DROP CONSTRAINT #{constraint}"
    validate = "ALTER TABLE #{table_name} VALIDATE CONSTRAINT #{constraint}"

    [{:add, Check.execute(add, drop)}, {:validate, Check.execute(validate, "")}]
  end

  defp migration(_model, _table, _column, _assoc), do: []
end
