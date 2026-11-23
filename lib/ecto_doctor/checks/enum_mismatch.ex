defmodule EctoDoctor.Checks.EnumMismatch do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Adapter
  alias EctoDoctor.Check
  alias EctoDoctor.Database.Constraint
  alias EctoDoctor.Schema

  @impl EctoDoctor.Check
  def id, do: :enum_mismatch

  @impl EctoDoctor.Check
  def explain do
    """
    Ecto.Enum values that differ from the database enum type or check constraint.

    A value only the schema knows fails on insert.
    A value only the database knows makes Ecto raise when it loads that row.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    schema.enum_values
    |> Enum.map(fn {field, values} ->
      %{
        field: field,
        values: values,
        database_values: database_values(table, Schema.column(schema, field))
      }
    end)
    |> Enum.filter(&differ?/1)
    |> Enum.map(&finding(model, schema, &1))
  end

  # Values the database doesn't list can't be compared
  defp differ?(%{database_values: nil}), do: false
  defp differ?(enum), do: Enum.sort(enum.values) != Enum.sort(enum.database_values)

  defp database_values(table, column_name) do
    case table.columns[column_name] do
      %{enum_values: [_ | _] = values} -> values
      _column -> check_values(table, column_name)
    end
  end

  # Reads the values out of a check like status IN ('a', 'b') or status = ANY (ARRAY['a', 'b'])
  # A check over numbers such as status IN (0, 1) has no quoted values so it can't be compared
  defp check_values(table, column_name) do
    with %Constraint{} = check <- Enum.find(table.constraints, &list_check?(&1, column_name)),
         [_ | _] = values <- Adapter.quoted_values(check.definition) do
      values
    else
      _none -> nil
    end
  end

  defp list_check?(
         %Constraint{kind: :check, columns: [column_name], definition: definition},
         column_name
       )
       when is_binary(definition) do
    definition |> String.upcase() |> String.contains?([" IN ", " ANY "])
  end

  defp list_check?(_constraint, _column_name), do: false

  defp finding(model, schema, enum) do
    missing = enum.values -- enum.database_values
    unknown = enum.database_values -- enum.values

    Check.finding(model, schema,
      check: id(),
      level: :error,
      columns: [Schema.column(schema, enum.field)],
      message: "#{enum.field} values differ. " <> difference(missing, unknown)
    )
  end

  defp difference(missing, []), do: "The database rejects #{inspect(missing)}."
  defp difference([], unknown), do: "The schema can't load #{inspect(unknown)}."

  defp difference(missing, unknown) do
    "The database rejects #{inspect(missing)} and the schema can't load #{inspect(unknown)}."
  end
end
