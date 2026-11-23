defmodule EctoDoctor.Checks.StringLengthOverflow do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Check
  alias EctoDoctor.Model
  alias EctoDoctor.Schema

  @impl EctoDoctor.Check
  def id, do: :string_length_overflow

  @impl EctoDoctor.Check
  def explain do
    """
    A string field cast from params into a column with a length limit and no validate_length.

    Ecto's migrations make :string columns varchar(255) by default.
    Longer input then fails in the database and raises instead of showing an error on the form.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    {cast_columns, _unknown_cast?} = Model.cast_columns(model, schema)

    schema.fields
    |> Enum.filter(fn {_field, type} -> type == :string end)
    |> Enum.map(fn {field, _type} -> {field, table.columns[Schema.column(schema, field)]} end)
    |> Enum.filter(fn {_field, column} -> limited?(column) and column.name in cast_columns end)
    |> Enum.reject(fn {field, column} -> validated?(model, schema, field, column.max_length) end)
    |> Enum.map(fn {field, column} -> finding(model, schema, field, column) end)
  end

  defp limited?(nil), do: false
  defp limited?(column), do: column.max_length != nil

  # A validate_length whose fields or limit can't be read counts as valid
  defp validated?(model, schema, field, limit) do
    model
    |> Model.rules(schema, :validate_length)
    |> Enum.any?(fn rule -> covers?(rule, field, limit) end)
  end

  defp covers?(%{fields: :unknown}, _field, _limit), do: true

  # A limit that can't be read might fit so it counts as covering the column
  defp covers?(rule, field, limit) do
    max = rule.opts[:max] || rule.opts[:is]
    field in rule.fields and (max == :unknown or (is_integer(max) and max <= limit))
  end

  defp finding(model, schema, field, column) do
    Check.finding(model, schema,
      check: id(),
      level: :error,
      columns: [column.name],
      message:
        "#{field} has no validate_length but its column holds #{column.max_length} characters.",
      fix: "|> validate_length(#{inspect(field)}, max: #{column.max_length})"
    )
  end
end
