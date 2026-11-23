defmodule EctoDoctor.Checks.TypeMismatch do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Adapter.SQLite
  alias EctoDoctor.Check
  alias EctoDoctor.Model
  alias EctoDoctor.Schema

  @datetimes [:naive_datetime, :naive_datetime_usec, :utc_datetime, :utc_datetime_usec]

  @exact_families %{
    "smallint" => :integer,
    "integer" => :integer,
    "bigint" => :integer,
    "int" => :integer,
    "tinyint" => :integer,
    "mediumint" => :integer,
    "uuid" => :uuid,
    "citext" => :string,
    "ltree" => :string,
    "hstore" => :json,
    "date" => :date,
    "boolean" => :boolean,
    "bool" => :boolean,
    "numeric" => :decimal,
    "decimal" => :decimal,
    "array" => :array
  }

  # Order matters since datetime contains time
  @partial_families [
    string: ["char", "text"],
    datetime: ["timestamp", "datetime"],
    time: ["time"],
    json: ["json"],
    float: ["double", "real", "float"],
    binary: ["bytea", "blob", "binary"]
  ]

  @impl EctoDoctor.Check
  def id, do: :type_mismatch

  @impl EctoDoctor.Check
  def explain do
    """
    A field whose Ecto type doesn't fit its column or a field with no column at all.

    Custom types compare through their underlying type and both timestamp and timestamptz fit UTC types.
    A _usec type on a column without microseconds is a warning because it drops them.

    Column types it doesn't know, such as ones from PostGIS or pgvector, are never reported.
    A custom Ecto type whose type is named like the column, such as :vector on a vector column, fits.
    Map your own types with `types: %{"my_type" => :string}` in this check's options.
    """
  end

  @impl EctoDoctor.Check
  def run(model, opts) do
    types = Keyword.get(opts, :types, %{})

    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table, types) end)
  end

  # SQLite stores any value in any column so only missing columns matter there
  defp check_table(%Model{database: %{adapter: SQLite}} = model, schema, table, _types) do
    schema.fields
    |> Enum.reject(fn {field, _type} ->
      Map.has_key?(table.columns, Schema.column(schema, field))
    end)
    |> Enum.map(fn {field, _type} -> finding(model, schema, field, missing_column(field)) end)
  end

  defp check_table(model, schema, table, types) do
    Enum.flat_map(schema.fields, fn {field, type} ->
      column = table.columns[Schema.column(schema, field)]

      case problem(field, base(type), column, types) do
        nil -> []
        problem -> [finding(model, schema, field, problem)]
      end
    end)
  end

  defp missing_column(field), do: {:error, "#{field} has no column in the database."}

  defp problem(field, _base, nil, _types), do: missing_column(field)

  defp problem(field, base, column, types) do
    {expected, family} =
      case Map.fetch(types, column.type) do
        {:ok, family} -> {expected(base), family}
        :error -> {expected(base), family(column.type)}
      end

    cond do
      to_string(base) == column.type ->
        precision(field, base, column)

      family == :other or is_nil(expected) ->
        precision(field, base, column)

      family not in expected ->
        {:error, "#{field} is #{base} in the schema but #{column.type} in the database."}

      true ->
        precision(field, base, column)
    end
  end

  # A column that doesn't state its precision keeps microseconds
  defp precision(field, base, %{precision: digits})
       when base in [:naive_datetime_usec, :utc_datetime_usec] and is_integer(digits) and
              digits < 6 do
    {:warning, "#{field} keeps microseconds but its column only keeps #{digits} digits."}
  end

  defp precision(_field, _base, _column), do: nil

  defp finding(model, schema, field, {level, message}) do
    Check.finding(model, schema,
      check: id(),
      level: level,
      columns: [Schema.column(schema, field)],
      message: message
    )
  end

  defp base({:parameterized, {Ecto.Embedded, _params}}), do: :embed
  defp base({:parameterized, Ecto.Embedded, _params}), do: :embed
  defp base({:parameterized, {Ecto.Enum, _params}}), do: :enum
  defp base({:parameterized, Ecto.Enum, _params}), do: :enum
  defp base({:parameterized, {module, params}}), do: base(module.type(params))
  defp base({:parameterized, module, params}), do: base(module.type(params))
  defp base({:array, _type}), do: :array
  defp base({:map, _type}), do: :map

  defp base(type) when is_atom(type) do
    cond do
      Ecto.Type.primitive?(type) -> type
      Code.ensure_loaded?(type) and function_exported?(type, :type, 0) -> base(type.type())
      true -> type
    end
  end

  defp base(_type), do: :unknown

  defp expected(type) when type in [:id, :integer], do: [:integer]
  defp expected(type) when type in [:binary_id, :uuid], do: [:uuid, :string, :binary]
  defp expected(:string), do: [:string]
  defp expected(:boolean), do: [:boolean, :integer]
  defp expected(:float), do: [:float, :decimal]
  defp expected(:decimal), do: [:decimal]
  defp expected(:map), do: [:json]
  defp expected(:embed), do: [:json, :array]
  defp expected(:array), do: [:array, :json]
  defp expected(:date), do: [:date]
  defp expected(type) when type in [:time, :time_usec], do: [:time]
  defp expected(type) when type in @datetimes, do: [:datetime]
  defp expected(:binary), do: [:binary]
  defp expected(:enum), do: [:string, :integer]
  defp expected(_type), do: nil

  defp family(type) do
    case Map.fetch(@exact_families, type) do
      {:ok, family} -> family
      :error -> partial_family(type)
    end
  end

  defp partial_family(type) do
    case Enum.find(@partial_families, fn {_family, parts} -> String.contains?(type, parts) end) do
      {family, _parts} -> family
      nil -> :other
    end
  end
end
