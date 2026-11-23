defmodule EctoDoctor.Adapter.SQLite do
  @moduledoc false

  @behaviour EctoDoctor.Adapter

  import EctoDoctor.Adapter, only: [rows: 3, at_least?: 2]

  alias EctoDoctor.Adapter.SQLite.CreateTable
  alias EctoDoctor.Database
  alias EctoDoctor.Database.Column
  alias EctoDoctor.Database.Constraint
  alias EctoDoctor.Database.Index
  alias EctoDoctor.Database.Table

  @tables "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"

  @impl EctoDoctor.Adapter
  def check_version(repo) do
    [%{"version" => version}] = rows(repo, "SELECT sqlite_version() AS version", [])

    if at_least?(version, {3, 35}) do
      :ok
    else
      {:error, "Ecto Doctor needs SQLite 3.35 or later. This is #{version}."}
    end
  end

  @impl EctoDoctor.Adapter
  def read(repo, _prefixes) do
    table_rows = rows(repo, @tables, [])
    statements = Map.new(table_rows, &{Map.fetch!(&1, "name"), Map.fetch!(&1, "sql")})

    tables =
      table_rows
      |> table_names()
      |> Map.new(fn name -> {{nil, name}, build_table(repo, name, statements[name])} end)

    Database.new(adapter: __MODULE__, default_prefix: nil, tables: tables)
  end

  # Virtual tables from extensions like FTS5 keep their data in shadow tables named after them
  defp table_names(rows) do
    virtual = for %{"name" => name, "sql" => "CREATE VIRTUAL TABLE" <> _rest} <- rows, do: name
    names = Enum.map(rows, &Map.fetch!(&1, "name"))

    Enum.reject(names, fn name -> name in virtual or shadow_table?(name, virtual) end)
  end

  defp shadow_table?(name, virtual), do: Enum.any?(virtual, &String.starts_with?(name, &1 <> "_"))

  defp build_table(repo, name, statement) do
    columns = pragma(repo, "table_info", name)
    indexes = pragma(repo, "index_list", name)
    foreign_keys = pragma(repo, "foreign_key_list", name)
    column_names = Enum.map(columns, &Map.fetch!(&1, "name"))

    Table.new(
      prefix: nil,
      name: name,
      columns: Map.new(columns, &build_column/1),
      indexes: Enum.map(indexes, &build_index(repo, &1)),
      constraints:
        build_foreign_keys(foreign_keys, name) ++
          Enum.map(CreateTable.checks(statement), &build_check(&1, column_names))
    )
  end

  # SQLite names an unnamed check by its expression when it fails so that is the name Ecto sees
  defp build_check(check, column_names) do
    Constraint.new(
      name: check.name || check.expression,
      kind: :check,
      columns: Enum.filter(column_names, &(&1 in check.identifiers)),
      definition: check.expression
    )
  end

  defp pragma(repo, pragma, name), do: rows(repo, "SELECT * FROM pragma_#{pragma}(?)", [name])

  # SQLite never enforces a length like VARCHAR(255) so a column has no limit to check
  defp build_column(%{"name" => name, "type" => declared, "notnull" => notnull, "pk" => pk}) do
    type = declared |> String.split("(") |> List.first() |> String.trim() |> String.downcase()

    column =
      Column.new(
        name: name,
        type: type,
        max_length: nil,
        precision: nil,
        nullable?: notnull == 0 and pk == 0,
        enum_values: nil
      )

    {name, column}
  end

  defp build_index(repo, %{
         "name" => name,
         "unique" => unique,
         "origin" => origin,
         "partial" => partial
       }) do
    columns =
      repo
      |> rows("SELECT name FROM pragma_index_info(?)", [name])
      |> Enum.map(&Map.fetch!(&1, "name"))

    Index.new(
      name: name,
      columns: columns,
      unique?: unique == 1,
      primary?: origin == "pk",
      partial?: partial == 1,
      expression?: Enum.any?(columns, &is_nil/1),
      method: "btree"
    )
  end

  # SQLite foreign keys have no names so Ecto's default name stands in
  defp build_foreign_keys(rows, table_name) do
    rows
    |> Enum.group_by(&Map.fetch!(&1, "id"))
    |> Enum.map(fn {_id, parts} -> build_foreign_key(parts, table_name) end)
  end

  defp build_foreign_key(
         [%{"table" => ref_table, "on_delete" => on_delete} | _rest] = parts,
         table_name
       ) do
    columns = Enum.map(parts, &Map.fetch!(&1, "from"))

    Constraint.new(
      name: "#{table_name}_#{Enum.join(columns, "_")}_fkey",
      kind: :foreign_key,
      columns: columns,
      references: {nil, ref_table, Enum.map(parts, &Map.fetch!(&1, "to"))},
      on_delete: on_delete
    )
  end
end
