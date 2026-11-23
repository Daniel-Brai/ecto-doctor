defmodule EctoDoctor.Schema do
  @moduledoc false

  alias Ecto.Association.BelongsTo
  alias Ecto.Association.Has
  alias Ecto.Association.HasThrough
  alias Ecto.Association.ManyToMany

  @type association :: %{
          name: atom(),
          kind: :belongs_to | :has_many | :has_one | :many_to_many,
          owner_key: atom(),
          related_key: nil | atom(),
          related: module(),
          related_source: nil | String.t(),
          related_prefix: nil | String.t(),
          on_delete: nil | atom(),
          join_through: nil | String.t()
        }

  @type t :: %__MODULE__{
          module: module(),
          source: String.t(),
          prefix: nil | String.t(),
          file: nil | String.t(),
          fields: %{atom() => term()},
          field_sources: %{atom() => String.t()},
          enum_values: %{atom() => [String.t()]},
          associations: [association()],
          primary_key: [atom()]
        }

  @enforce_keys [:module, :source]
  defstruct [
    :module,
    :source,
    :prefix,
    :file,
    fields: %{},
    field_sources: %{},
    enum_values: %{},
    associations: [],
    primary_key: []
  ]

  @doc "Lists every module of an app and loads the app first."
  @spec modules(atom()) :: [module()]
  def modules(app) do
    Application.load(app)

    case :application.get_key(app, :modules) do
      {:ok, modules} -> modules
      :undefined -> []
    end
  end

  @doc "Reads every Ecto schema among the modules."
  @spec all([module()]) :: [t()]
  def all(modules) do
    modules
    |> Enum.filter(&schema?/1)
    |> Enum.map(&from_module/1)
  end

  defp schema?(module) do
    ecto? = Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 2)
    ecto? and reflect(module, :source) != nil
  end

  @spec from_module(module()) :: t()
  def from_module(module) do
    fields = reflect(module, :fields)
    types = Map.new(fields, fn field -> {field, reflect(module, :type, field)} end)

    sources =
      Map.new(fields, fn field -> {field, to_string(reflect(module, :field_source, field))} end)

    associations =
      module
      |> reflect(:associations)
      |> Enum.map(&reflect(module, :association, &1))
      |> Enum.reject(&through?/1)
      |> Enum.map(&association/1)

    %__MODULE__{
      module: module,
      source: reflect(module, :source),
      prefix: reflect(module, :prefix),
      file: source_file(module),
      fields: types,
      field_sources: sources,
      enum_values: enum_values(module, fields),
      associations: associations,
      primary_key: reflect(module, :primary_key)
    }
  end

  @spec column(t(), atom()) :: String.t()
  def column(%__MODULE__{} = schema, field), do: schema.field_sources[field] || to_string(field)

  @spec source_file(module()) :: nil | String.t()
  def source_file(module) do
    case module.module_info(:compile)[:source] do
      nil -> nil
      source -> source |> to_string() |> Path.relative_to_cwd()
    end
  end

  defp enum_values(module, fields) do
    for field <- fields, enum?(reflect(module, :type, field)), into: %{} do
      values = module |> Ecto.Enum.dump_values(field) |> Enum.map(&to_string/1)
      {field, values}
    end
  end

  defp enum?({:parameterized, {Ecto.Enum, _params}}), do: true
  defp enum?({:parameterized, Ecto.Enum, _params}), do: true
  defp enum?({:array, type}), do: enum?(type)
  defp enum?(_type), do: false

  # A through association walks other associations and has no keys or columns of its own
  defp through?(%HasThrough{}), do: true
  defp through?(_assoc), do: false

  defp association(assoc) do
    %{
      name: assoc.field,
      kind: kind(assoc),
      owner_key: assoc.owner_key,
      related_key: Map.get(assoc, :related_key),
      related: assoc.related,
      related_source: related_source(assoc),
      related_prefix: related_info(assoc.related, :prefix),
      on_delete: Map.get(assoc, :on_delete),
      join_through: join_through(assoc)
    }
  end

  defp kind(%BelongsTo{}), do: :belongs_to
  defp kind(%Has{cardinality: :many}), do: :has_many
  defp kind(%Has{cardinality: :one}), do: :has_one
  defp kind(%ManyToMany{}), do: :many_to_many

  defp join_through(%ManyToMany{join_through: table}) when is_binary(table), do: table
  defp join_through(%ManyToMany{join_through: schema}), do: reflect(schema, :source)
  defp join_through(_assoc), do: nil

  # The related module may not be compiled as a schema, for example a polymorphic association
  # An association like has_many :comments, {"post_comments", Comment} reads another table
  defp related_source(%{queryable: {source, _schema}}), do: source
  defp related_source(assoc), do: related_info(assoc.related, :source)

  defp related_info(related, key) do
    if schema?(related), do: reflect(related, key)
  end

  defp reflect(module, key), do: module.__schema__(key)
  defp reflect(module, key, arg), do: module.__schema__(key, arg)
end
