defmodule EctoDoctor.Checks.MissingNotNull do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Adapter.Postgres
  alias EctoDoctor.Check
  alias EctoDoctor.Model
  alias EctoDoctor.Schema

  @impl EctoDoctor.Check
  def id, do: :missing_not_null

  @impl EctoDoctor.Check
  def explain do
    """
    A field in validate_required whose column allows NULL.

    The changeset keeps NULL out but any other write can still put it in.
    Repo.update_all, a script or another app sharing the database can all write NULL.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    required_fields =
      model
      |> Model.rules(schema, :validate_required)
      |> Enum.reject(&(&1.fields == :unknown))
      |> Enum.flat_map(& &1.fields)
      |> Enum.uniq()

    required_fields
    |> Enum.map(&table.columns[Schema.column(schema, &1)])
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(& &1.nullable?)
    |> Enum.map(&finding(model, schema, table, &1))
  end

  defp finding(model, schema, table, column) do
    Check.finding(model, schema,
      check: id(),
      level: :warning,
      columns: [column.name],
      message: "#{column.name} is required in a changeset but the column allows NULL.",
      migration: migration(model, table, column)
    )
  end

  # A NOT VALID check lets new rows in without scanning the table
  # Validating it later doesn't block writes and lets SET NOT NULL skip its own scan
  defp migration(%Model{database: %{adapter: Postgres}}, table, column) do
    table_name = Check.sql_name(table.prefix, table.name)
    column_name = Check.sql_name(nil, column.name)
    check = Check.sql_name(nil, "#{table.name}_#{column.name}_not_null")

    add_check =
      "ALTER TABLE #{table_name} ADD CONSTRAINT #{check} CHECK (#{column_name} IS NOT NULL) NOT VALID"

    drop_check = "ALTER TABLE #{table_name} DROP CONSTRAINT #{check}"
    validate_check = "ALTER TABLE #{table_name} VALIDATE CONSTRAINT #{check}"
    set_not_null = "ALTER TABLE #{table_name} ALTER COLUMN #{column_name} SET NOT NULL"
    drop_not_null = "ALTER TABLE #{table_name} ALTER COLUMN #{column_name} DROP NOT NULL"

    [
      {:add, Check.execute(add_check, drop_check)},
      {:validate, Check.execute(validate_check, "")},
      {:validate, Check.execute(set_not_null, drop_not_null)},
      {:validate, Check.execute(drop_check, add_check)}
    ]
  end

  defp migration(_model, _table, _column), do: []
end
