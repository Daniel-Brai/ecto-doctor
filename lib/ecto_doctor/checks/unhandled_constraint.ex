defmodule EctoDoctor.Checks.UnhandledConstraint do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Adapter.SQLite
  alias EctoDoctor.Check
  alias EctoDoctor.Database.Constraint
  alias EctoDoctor.Model
  alias EctoDoctor.Schema

  @rule_kinds %{
    unique: [:unique_constraint],
    foreign_key: [:foreign_key_constraint, :assoc_constraint],
    check: [:check_constraint],
    exclusion: [:exclusion_constraint]
  }

  @calls %{
    unique: "unique_constraint",
    foreign_key: "foreign_key_constraint",
    check: "check_constraint",
    exclusion: "exclusion_constraint"
  }

  @impl EctoDoctor.Check
  def id, do: :unhandled_constraint

  @impl EctoDoctor.Check
  def explain do
    """
    A constraint in the database that no changeset handles.

    When a write breaks it Ecto raises Ecto.ConstraintError instead of returning a changeset with an error.
    Users see a crash where they should see a message on the form.

    It is an error when a changeset casts one of the constraint's columns because user input can break it.
    A foreign key is a warning then since ids usually come from your own code.
    It is info when only your own code writes those columns.
    A check on Ecto.Enum columns is left out because the cast already rejects unknown values.
    So are foreign keys on SQLite since it never says which key failed and no changeset can catch that.
    """
  end

  @impl EctoDoctor.Check
  def run(model, _opts) do
    model
    |> Check.tables()
    |> Enum.flat_map(fn {schema, table} -> check_table(model, schema, table) end)
  end

  defp check_table(model, schema, table) do
    table
    |> constraints()
    |> Enum.reject(&left_out?(model, schema, &1))
    |> Enum.map(&finding(model, schema, &1))
  end

  # A unique constraint also creates a unique index of the same name so the index stands for both
  defp constraints(table) do
    unique_indexes =
      table.indexes
      |> Enum.filter(fn index -> index.unique? and not index.primary? end)
      |> Enum.map(fn index ->
        Constraint.new(name: index.name, kind: :unique, columns: index.columns)
      end)

    others = Enum.reject(table.constraints, &(&1.kind == :unique))

    unique_indexes ++ others
  end

  defp handled?(model, schema, constraint) do
    rules = Model.rules(model, schema, Map.fetch!(@rule_kinds, constraint.kind))
    Enum.any?(rules, &matches?(&1, schema, constraint.name))
  end

  # A rule whose name can't be read may handle any constraint so it counts as handled
  defp matches?(rule, schema, name) do
    case {Check.constraint_name(rule, schema), rule.opts[:match]} do
      {nil, _match} -> true
      {_rule_name, :unknown} -> true
      {rule_name, :suffix} -> String.ends_with?(name, rule_name)
      {rule_name, :prefix} -> String.starts_with?(name, rule_name)
      {rule_name, _exact} -> rule_name == name
    end
  end

  defp left_out?(model, schema, constraint) do
    nameless?(model, constraint) or handled?(model, schema, constraint) or
      enum_check?(schema, constraint)
  end

  # SQLite never says which foreign key failed so no changeset can catch it
  defp nameless?(%Model{database: %{adapter: SQLite}}, %Constraint{kind: :foreign_key}), do: true
  defp nameless?(_model, _constraint), do: false

  # Ecto.Enum rejects unknown values in the cast so a check on enum columns can't be reached
  # enum_mismatch reports the case where the values disagree
  defp enum_check?(schema, %Constraint{kind: :check, columns: [_ | _] = columns}) do
    enum_columns = Enum.map(Map.keys(schema.enum_values), &Schema.column(schema, &1))
    Enum.all?(columns, &(&1 in enum_columns))
  end

  defp enum_check?(_schema, _constraint), do: false

  defp finding(model, schema, constraint) do
    call = Map.fetch!(@calls, constraint.kind)
    fields = Enum.map(constraint.columns, &Check.field(schema, &1))

    Check.finding(model, schema,
      check: id(),
      level: level(constraint.kind, cast(model, schema, constraint)),
      columns: constraint.columns,
      message: "No changeset handles #{constraint.name}. Bad input raises Ecto.ConstraintError.",
      fix:
        "|> #{call}(#{inspect(field_arg(constraint.kind, fields))}, name: #{inspect(constraint.name)})"
    )
  end

  # A cast whose fields can't be read might cast these columns too
  defp cast(model, schema, constraint) do
    {cast_columns, unknown_cast?} = Model.cast_columns(model, schema)

    cond do
      Enum.any?(constraint.columns, &(&1 in cast_columns)) -> :cast
      unknown_cast? -> :maybe
      true -> :none
    end
  end

  # Ids usually come from your own code after a lookup so a foreign key is never an error
  defp level(:foreign_key, :cast), do: :warning
  defp level(_kind, :cast), do: :error
  defp level(_kind, :maybe), do: :warning
  defp level(_kind, :none), do: :info

  defp field_arg(:unique, [field]), do: field
  defp field_arg(:unique, fields), do: fields
  defp field_arg(_kind, [field | _rest]), do: field
  defp field_arg(_kind, []), do: :base
end
