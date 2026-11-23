defmodule EctoDoctor.Check do
  @moduledoc false

  alias EctoDoctor.Adapter.Postgres
  alias EctoDoctor.Database.Table
  alias EctoDoctor.Finding
  alias EctoDoctor.Model
  alias EctoDoctor.Rule
  alias EctoDoctor.Schema

  @callback id() :: atom()
  @callback explain() :: String.t()
  @callback run(Model.t(), keyword()) :: [Finding.t()]

  @spec tables(Model.t()) :: [{Schema.t(), Table.t()}]
  def tables(%Model{} = model) do
    model.schemas
    |> Enum.map(fn schema -> {schema, Model.table(model, schema)} end)
    |> Enum.reject(fn {_schema, table} -> is_nil(table) end)
  end

  @spec finding(Model.t(), Schema.t(), keyword()) :: Finding.t()
  def finding(%Model{} = model, %Schema{} = schema, fields) do
    table = Model.table(model, schema)

    defaults = [
      schema: schema.module,
      file: schema.file,
      line: Model.line(model, schema),
      table: table_name(model, table)
    ]

    struct!(Finding, Keyword.merge(defaults, fields))
  end

  @spec table_name(Model.t(), Table.t()) :: String.t()
  def table_name(%Model{} = model, %Table{} = table) do
    if default_prefix?(model, table) do
      table.name
    else
      "#{table.prefix}.#{table.name}"
    end
  end

  @spec index_args(Model.t(), Table.t()) :: {String.t(), String.t()}
  def index_args(%Model{} = model, %Table{} = table) do
    prefix = if default_prefix?(model, table), do: "", else: ", prefix: #{literal(table.prefix)}"

    concurrently =
      case model.database.adapter do
        Postgres -> ", concurrently: true"
        _adapter -> ""
      end

    {migration_name(table.name), prefix <> concurrently}
  end

  @spec summary(module()) :: String.t()
  def summary(check) do
    [summary | _rest] = String.split(check.explain(), "\n")
    summary
  end

  @spec migration_names([String.t()]) :: String.t()
  def migration_names(names), do: "[" <> Enum.map_join(names, ", ", &migration_name/1) <> "]"

  defp migration_name(name) do
    if plain_name?(name), do: ":" <> name, else: ":" <> literal(name)
  end

  # A name like users_2 can be written as an atom without quotes while userId needs :"userId"
  # A string would be read by Ecto as raw SQL instead of a name
  # nil, true and false are written :nil and so on but those atoms aren't names
  defp plain_name?(name) when name in ~w[nil true false], do: false

  defp plain_name?(<<first, rest::binary>>) when first in ?a..?z do
    rest
    |> String.to_charlist()
    |> Enum.all?(&(&1 in ?a..?z or &1 in ?0..?9 or &1 == ?_))
  end

  defp plain_name?(_name), do: false

  @spec sql_name(nil | String.t(), String.t()) :: String.t()
  def sql_name(nil, name), do: quote_name(name)
  def sql_name(prefix, name), do: quote_name(prefix) <> "." <> quote_name(name)

  @spec execute(String.t(), String.t()) :: String.t()
  def execute(up, down), do: "execute(#{literal(up)}, #{literal(down)})"

  @doc "Writes text as an Elixir string literal for generated code, however long it is."
  @spec literal(String.t()) :: String.t()
  def literal(text), do: inspect(text, printable_limit: :infinity)

  @spec constraint_name(Rule.t(), Schema.t()) :: nil | String.t()
  def constraint_name(%Rule{} = rule, %Schema{} = schema) do
    case rule.opts[:name] do
      nil -> default_name(rule, schema)
      :unknown -> nil
      name -> to_string(name)
    end
  end

  @spec field(Schema.t(), String.t()) :: atom() | String.t()
  def field(%Schema{} = schema, column) do
    case Enum.find(schema.field_sources, fn {_field, source} -> source == column end) do
      {field, _source} -> field
      nil -> column
    end
  end

  defp default_prefix?(model, table), do: table.prefix in [nil, model.database.default_prefix]

  defp quote_name(name) do
    escaped = String.replace(name, "\"", "\"\"")
    "\"#{escaped}\""
  end

  defp default_name(%Rule{fields: :unknown}, _schema), do: nil

  defp default_name(%Rule{kind: :unique_constraint} = rule, schema) do
    columns = Enum.map_join(rule.fields, "_", &Schema.column(schema, &1))
    "#{schema.source}_#{columns}_index"
  end

  defp default_name(%Rule{kind: :foreign_key_constraint, fields: [field | _rest]}, schema) do
    "#{schema.source}_#{Schema.column(schema, field)}_fkey"
  end

  defp default_name(%Rule{kind: :assoc_constraint, fields: [name | _rest]}, schema) do
    case Enum.find(schema.associations, &(&1.name == name)) do
      nil -> nil
      assoc -> "#{schema.source}_#{Schema.column(schema, assoc.owner_key)}_fkey"
    end
  end

  defp default_name(%Rule{kind: :exclusion_constraint, fields: [field | _rest]}, schema) do
    "#{schema.source}_#{Schema.column(schema, field)}_exclusion"
  end

  defp default_name(_rule, _schema), do: nil
end
