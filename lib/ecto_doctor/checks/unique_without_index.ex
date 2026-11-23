defmodule EctoDoctor.Checks.UniqueWithoutIndex do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Check
  alias EctoDoctor.Model
  alias EctoDoctor.Schema

  @impl EctoDoctor.Check
  def id, do: :unique_without_index

  @impl EctoDoctor.Check
  def explain do
    """
    A unique_constraint with no unique index of that name.

    The constraint only turns a database error into a changeset error.
    Without an index of that name the rule never fires and a duplicate either gets in or raises Ecto.ConstraintError.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    index_names = for index <- table.indexes, index.unique?, do: index.name

    model
    |> Model.rules(schema, :unique_constraint)
    |> Enum.filter(&missing_index?(&1, schema, index_names))
    |> Enum.map(&finding(model, schema, table, &1))
  end

  # A rule with fields it can't read or a prefix or suffix match may point at any index
  defp missing_index?(rule, schema, index_names) do
    name = Check.constraint_name(rule, schema)
    exact? = rule.opts[:match] in [nil, :exact]
    rule.fields != :unknown and exact? and name != nil and name not in index_names
  end

  defp finding(model, schema, table, rule) do
    name = Check.constraint_name(rule, schema)
    columns = Enum.map(rule.fields, &Schema.column(schema, &1))
    {table_arg, options} = Check.index_args(model, table)
    column_args = Check.migration_names(columns)

    Check.finding(model, schema,
      check: id(),
      level: :error,
      columns: columns,
      file: rule.file,
      line: rule.line,
      message: "unique_constraint expects a unique index named #{name} but there is none.",
      migration: [
        {:concurrent,
         "create unique_index(#{table_arg}, #{column_args}, name: #{Check.literal(name)}#{options})"}
      ]
    )
  end
end
