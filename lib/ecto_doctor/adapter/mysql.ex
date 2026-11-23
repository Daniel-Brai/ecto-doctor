defmodule EctoDoctor.Adapter.MySQL do
  @moduledoc false

  @behaviour EctoDoctor.Adapter

  import EctoDoctor.Adapter, only: [rows: 3, table_key: 1, at_least?: 2, quoted_values: 1]

  alias EctoDoctor.Database
  alias EctoDoctor.Database.Column
  alias EctoDoctor.Database.Constraint
  alias EctoDoctor.Database.Index
  alias EctoDoctor.Database.Table

  @columns """
  SELECT
    c.TABLE_SCHEMA AS prefix,
    c.TABLE_NAME AS table_name,
    c.COLUMN_NAME AS name,
    c.DATA_TYPE AS type,
    c.COLUMN_TYPE AS column_type,
    c.CHARACTER_MAXIMUM_LENGTH AS max_length,
    c.DATETIME_PRECISION AS `precision`,
    c.IS_NULLABLE AS nullable
  FROM information_schema.COLUMNS c
  JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
  WHERE FIND_IN_SET(c.TABLE_SCHEMA, ?) AND t.TABLE_TYPE = 'BASE TABLE'
  """

  @indexes """
  SELECT
    TABLE_SCHEMA AS prefix,
    TABLE_NAME AS table_name,
    INDEX_NAME AS name,
    NON_UNIQUE AS non_unique,
    INDEX_TYPE AS method,
    COLUMN_NAME AS column_name
  FROM information_schema.STATISTICS
  WHERE FIND_IN_SET(TABLE_SCHEMA, ?)
  ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX
  """

  @foreign_keys """
  SELECT
    k.TABLE_SCHEMA AS prefix,
    k.TABLE_NAME AS table_name,
    k.CONSTRAINT_NAME AS name,
    k.COLUMN_NAME AS column_name,
    k.REFERENCED_TABLE_SCHEMA AS ref_prefix,
    k.REFERENCED_TABLE_NAME AS ref_table,
    k.REFERENCED_COLUMN_NAME AS ref_column,
    r.DELETE_RULE AS on_delete
  FROM information_schema.KEY_COLUMN_USAGE k
  JOIN information_schema.REFERENTIAL_CONSTRAINTS r
    ON r.CONSTRAINT_SCHEMA = k.TABLE_SCHEMA AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
  WHERE FIND_IN_SET(k.TABLE_SCHEMA, ?)
  ORDER BY k.TABLE_NAME, k.CONSTRAINT_NAME, k.ORDINAL_POSITION
  """

  @checks """
  SELECT
    t.TABLE_SCHEMA AS prefix,
    t.TABLE_NAME AS table_name,
    c.CONSTRAINT_NAME AS name,
    c.CHECK_CLAUSE AS definition
  FROM information_schema.CHECK_CONSTRAINTS c
  JOIN information_schema.TABLE_CONSTRAINTS t
    ON t.CONSTRAINT_SCHEMA = c.CONSTRAINT_SCHEMA AND t.CONSTRAINT_NAME = c.CONSTRAINT_NAME
  WHERE FIND_IN_SET(t.TABLE_SCHEMA, ?) AND t.CONSTRAINT_TYPE = 'CHECK'
  """

  # MariaDB names checks per table so CONSTRAINT_1 repeats and the join needs the table too
  @mariadb_checks """
  SELECT
    t.TABLE_SCHEMA AS prefix,
    t.TABLE_NAME AS table_name,
    c.CONSTRAINT_NAME AS name,
    c.CHECK_CLAUSE AS definition
  FROM information_schema.CHECK_CONSTRAINTS c
  JOIN information_schema.TABLE_CONSTRAINTS t
    ON t.CONSTRAINT_SCHEMA = c.CONSTRAINT_SCHEMA
    AND t.CONSTRAINT_NAME = c.CONSTRAINT_NAME
    AND t.TABLE_NAME = c.TABLE_NAME
  WHERE FIND_IN_SET(t.TABLE_SCHEMA, ?) AND t.CONSTRAINT_TYPE = 'CHECK'
  """

  @impl EctoDoctor.Adapter
  def check_version(repo) do
    [%{"version" => version}] = rows(repo, "SELECT VERSION() AS version", [])

    {database, minimum} = minimum_version(version)

    if at_least?(version, minimum) do
      :ok
    else
      {:error, "Ecto Doctor needs #{database} or later. This is #{version}."}
    end
  end

  defp mariadb?(version), do: String.contains?(version, "MariaDB")

  defp minimum_version(version) do
    if mariadb?(version) do
      {"MariaDB 10.11", {10, 11}}
    else
      {"MySQL 8.4", {8, 4}}
    end
  end

  @impl EctoDoctor.Adapter
  def read(repo, prefixes) do
    [%{"db" => default, "version" => version}] =
      rows(repo, "SELECT DATABASE() AS db, VERSION() AS version", [])

    checks = if mariadb?(version), do: @mariadb_checks, else: @checks

    schemas = prefixes |> Enum.map(&(&1 || default)) |> Enum.uniq() |> Enum.join(",")

    catalog = %{
      indexes: repo |> rows(@indexes, [schemas]) |> Enum.group_by(&table_key/1),
      foreign_keys: repo |> rows(@foreign_keys, [schemas]) |> Enum.group_by(&table_key/1),
      checks: repo |> rows(checks, [schemas]) |> Enum.group_by(&table_key/1)
    }

    tables =
      repo
      |> rows(@columns, [schemas])
      |> Enum.group_by(&table_key/1)
      |> Map.new(fn {key, columns} -> {key, build_table(key, columns, catalog)} end)

    Database.new(adapter: __MODULE__, default_prefix: default, tables: tables)
  end

  defp build_table({prefix, name} = key, columns, catalog) do
    indexes = catalog.indexes |> Map.get(key, []) |> Enum.chunk_by(&Map.fetch!(&1, "name"))

    foreign_keys =
      catalog.foreign_keys |> Map.get(key, []) |> Enum.chunk_by(&Map.fetch!(&1, "name"))

    checks = Map.get(catalog.checks, key, [])
    column_names = Enum.map(columns, &Map.fetch!(&1, "name"))

    constraints =
      Enum.map(foreign_keys, &build_foreign_key/1) ++
        Enum.map(checks, &build_check(&1, column_names))

    Table.new(
      prefix: prefix,
      name: name,
      columns: Map.new(columns, &build_column/1),
      indexes: Enum.map(indexes, &build_index/1),
      constraints: constraints
    )
  end

  defp build_column(%{
         "name" => name,
         "type" => type,
         "column_type" => column_type,
         "max_length" => max_length,
         "precision" => precision,
         "nullable" => nullable
       }) do
    column =
      Column.new(
        name: name,
        type: type,
        max_length: length_limit(type, max_length),
        precision: precision,
        nullable?: nullable == "YES",
        enum_values: enum_values(type, column_type)
      )

    {name, column}
  end

  # TEXT and ENUM columns report a length too but only varchar and char reject longer values
  defp length_limit(type, max_length) when type in ["varchar", "char"], do: max_length
  defp length_limit(_type, _max_length), do: nil

  # An enum column type reads enum('a','b') so every second piece between quotes is a value
  defp enum_values("enum", column_type), do: quoted_values(column_type)

  defp enum_values(_type, _column_type), do: nil

  # A functional key part has no column name
  defp build_index(
         [%{"name" => name, "non_unique" => non_unique, "method" => method} | _rest] = parts
       ) do
    columns = Enum.map(parts, &Map.fetch!(&1, "column_name"))

    Index.new(
      name: name,
      columns: columns,
      unique?: non_unique == 0,
      primary?: name == "PRIMARY",
      partial?: false,
      expression?: Enum.any?(columns, &is_nil/1),
      method: method
    )
  end

  defp build_foreign_key(
         [
           %{
             "name" => name,
             "ref_prefix" => ref_prefix,
             "ref_table" => ref_table,
             "on_delete" => on_delete
           }
           | _rest
         ] = parts
       ) do
    Constraint.new(
      name: name,
      kind: :foreign_key,
      columns: Enum.map(parts, &Map.fetch!(&1, "column_name")),
      references: {ref_prefix, ref_table, Enum.map(parts, &Map.fetch!(&1, "ref_column"))},
      on_delete: on_delete
    )
  end

  # MySQL doesn't list a check's columns so they're the column names its clause quotes
  defp build_check(%{"name" => name, "definition" => definition}, column_names) do
    columns = Enum.filter(column_names, &String.contains?(definition, "`#{&1}`"))
    Constraint.new(name: name, kind: :check, columns: columns, definition: definition)
  end
end
