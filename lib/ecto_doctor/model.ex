defmodule EctoDoctor.Model do
  @moduledoc false

  alias EctoDoctor.Adapter
  alias EctoDoctor.Database
  alias EctoDoctor.Database.Table
  alias EctoDoctor.Error
  alias EctoDoctor.Rule
  alias EctoDoctor.Schema
  alias EctoDoctor.Source

  @type t :: %__MODULE__{
          repo: Ecto.Repo.t(),
          database: Database.t(),
          schemas: [Schema.t()],
          rules: [Rule.t()],
          ignores: %{module() => [atom()]},
          schema_lines: %{module() => nil | pos_integer()}
        }

  @enforce_keys [:repo, :database]
  defstruct [:repo, :database, schemas: [], rules: [], ignores: %{}, schema_lines: %{}]

  @spec build(Ecto.Repo.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def build(repo, opts) do
    apps = Keyword.get(opts, :apps, [repo.config()[:otp_app]])
    modules = Enum.flat_map(apps, &Schema.modules/1)

    schemas = Schema.all(modules)

    source =
      modules
      |> Enum.map(&Schema.source_file/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Source.read()

    prefixes = Enum.uniq([nil | Enum.map(schemas, & &1.prefix)])

    with {:ok, adapter} <- Adapter.for_repo(repo),
         :ok <- adapter.check_version(repo) do
      model = %__MODULE__{
        repo: repo,
        database: adapter.read(repo, prefixes),
        schemas: schemas,
        rules: assign_schemas(source, schemas),
        ignores: Map.new(source, fn {module, info} -> {module, info.ignore} end),
        schema_lines: Map.new(source, fn {module, info} -> {module, info.schema_line} end)
      }

      {:ok, model}
    else
      {:error, message} -> {:error, %Error{message: message}}
    end
  end

  @spec table(t(), Schema.t()) :: nil | Table.t()
  def table(%__MODULE__{} = model, %Schema{} = schema) do
    Database.table(model.database, schema.prefix, schema.source)
  end

  @spec rules(t(), Schema.t(), Rule.kind() | [Rule.kind()]) :: [Rule.t()]
  def rules(%__MODULE__{} = model, %Schema{module: module}, kinds) do
    kinds = List.wrap(kinds)
    Enum.filter(model.rules, fn rule -> rule.schema == module and rule.kind in kinds end)
  end

  @doc "Returns the columns a changeset casts and whether any cast had fields it couldn't read."
  @spec cast_columns(t(), Schema.t()) :: {MapSet.t(String.t()), boolean()}
  def cast_columns(%__MODULE__{} = model, %Schema{} = schema) do
    casts = rules(model, schema, :cast)
    {unknown, known} = Enum.split_with(casts, fn rule -> rule.fields == :unknown end)

    columns =
      for rule <- known, field <- rule.fields, into: MapSet.new() do
        Schema.column(schema, field)
      end

    {columns, unknown != []}
  end

  @spec line(t(), Schema.t()) :: nil | pos_integer()
  def line(%__MODULE__{} = model, %Schema{module: module}), do: model.schema_lines[module]

  # A changeset belongs to the schema in its function head or else its own module or its parent
  defp assign_schemas(source, schemas) do
    names = MapSet.new(schemas, & &1.module)

    for {_module, info} <- source, rule <- info.rules do
      owners = [rule.struct, rule.module, parent(rule.module)]
      %{rule | schema: Enum.find(owners, &MapSet.member?(names, &1))}
    end
  end

  defp parent(module) do
    case module |> Module.split() |> Enum.drop(-1) do
      [] -> nil
      parts -> Module.concat(parts)
    end
  end
end
