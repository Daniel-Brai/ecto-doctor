defmodule EctoDoctor.Adapter.Postgres do
  @moduledoc false

  @behaviour EctoDoctor.Adapter

  import EctoDoctor.Adapter, only: [rows: 3, table_key: 1]

  alias Ecto.Adapters.SQL
  alias EctoDoctor.Database
  alias EctoDoctor.Database.Column
  alias EctoDoctor.Database.Constraint
  alias EctoDoctor.Database.Index
  alias EctoDoctor.Database.Table

  @columns """
  SELECT
    c.table_schema AS prefix,
    c.table_name,
    c.column_name,
    c.data_type,
    c.udt_name,
    c.character_maximum_length,
    c.datetime_precision,
    c.is_nullable,
    (
      SELECT array_agg(e.enumlabel ORDER BY e.enumsortorder)
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      JOIN pg_enum e ON e.enumtypid = t.oid
      WHERE t.typname = c.udt_name AND n.nspname = c.udt_schema
    ) AS enum_values
  FROM information_schema.columns c
  JOIN pg_class r ON r.oid = format('%I.%I', c.table_schema, c.table_name)::regclass
  WHERE c.table_schema = ANY($1)
    AND r.relkind IN ('r', 'p')
    AND NOT r.relispartition
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = r.oid AND d.deptype = 'e')
  """

  @indexes """
  SELECT
    n.nspname AS prefix,
    t.relname AS table_name,
    i.relname AS name,
    ix.indisunique AS unique,
    ix.indisprimary AS primary,
    ix.indpred IS NOT NULL AS partial,
    ix.indexprs IS NOT NULL AS expression,
    am.amname AS method,
    ARRAY(
      SELECT a.attname
      FROM unnest((ix.indkey::int2[])[0:ix.indnkeyatts - 1]) WITH ORDINALITY k(attnum, ord)
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
      ORDER BY k.ord
    ) AS columns
  FROM pg_index ix
  JOIN pg_class t ON t.oid = ix.indrelid
  JOIN pg_class i ON i.oid = ix.indexrelid
  JOIN pg_am am ON am.oid = i.relam
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = ANY($1)
  """

  @constraints """
  SELECT
    n.nspname AS prefix,
    t.relname AS table_name,
    c.conname AS name,
    c.contype AS kind,
    pg_get_constraintdef(c.oid) AS definition,
    c.confdeltype AS on_delete,
    rn.nspname AS ref_prefix,
    rt.relname AS ref_table,
    ARRAY(
      SELECT a.attname
      FROM unnest(c.conkey) WITH ORDINALITY k(attnum, ord)
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
      ORDER BY k.ord
    ) AS columns,
    ARRAY(
      SELECT a.attname
      FROM unnest(c.confkey) WITH ORDINALITY k(attnum, ord)
      JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.attnum
      ORDER BY k.ord
    ) AS ref_columns
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  LEFT JOIN pg_class rt ON rt.oid = c.confrelid
  LEFT JOIN pg_namespace rn ON rn.oid = rt.relnamespace
  WHERE c.contype IN ('u', 'f', 'c', 'x') AND n.nspname = ANY($1)
  """

  @stats """
  SELECT
    schemaname AS prefix,
    relname AS table_name,
    n_live_tup AS live_rows,
    seq_scan AS seq_scans,
    coalesce(idx_scan, 0) AS index_scans
  FROM pg_stat_user_tables
  WHERE schemaname = ANY($1)
  """

  @slow_queries """
  SELECT
    query,
    calls,
    mean_exec_time AS mean_ms
  FROM pg_stat_statements
  WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND userid = (SELECT oid FROM pg_roles WHERE rolname = current_user)
    AND (ltrim(query) ILIKE 'select%' OR ltrim(query) ILIKE 'with%')
  ORDER BY mean_exec_time DESC
  LIMIT 10
  """

  @kinds %{"u" => :unique, "c" => :check, "x" => :exclusion}

  # A table that was never analyzed has no stats row
  @no_stats %{"live_rows" => 0, "seq_scans" => 0, "index_scans" => 0}

  @delete_actions %{
    "a" => "NO ACTION",
    "r" => "RESTRICT",
    "c" => "CASCADE",
    "n" => "SET NULL",
    "d" => "SET DEFAULT"
  }

  @impl EctoDoctor.Adapter
  def check_version(repo) do
    [%{"server_version_num" => number}] = rows(repo, "SHOW server_version_num", [])
    version = String.to_integer(number)

    if version >= 150_000 do
      :ok
    else
      {:error, "Ecto Doctor needs PostgreSQL 15 or later. This is #{div(version, 10_000)}."}
    end
  end

  @impl EctoDoctor.Adapter
  def read(repo, prefixes) do
    # A schema without a prefix lives in the first schema of the search path
    [%{"schema" => default_prefix}] = rows(repo, "SELECT current_schema() AS schema", [])
    prefixes = prefixes |> Enum.map(&(&1 || default_prefix)) |> Enum.uniq()

    catalog = %{
      indexes: repo |> rows(@indexes, [prefixes]) |> Enum.group_by(&table_key/1),
      constraints: repo |> rows(@constraints, [prefixes]) |> Enum.group_by(&table_key/1),
      stats: repo |> rows(@stats, [prefixes]) |> Map.new(fn row -> {table_key(row), row} end)
    }

    tables =
      repo
      |> rows(@columns, [prefixes])
      |> Enum.group_by(&table_key/1)
      |> Map.new(fn {key, columns} -> {key, build_table(key, columns, catalog)} end)

    Database.new(
      adapter: __MODULE__,
      default_prefix: default_prefix,
      tables: tables,
      slow_queries: slow_queries(repo)
    )
  end

  defp build_table({prefix, name} = key, columns, catalog) do
    indexes = Map.get(catalog.indexes, key, [])
    constraints = Map.get(catalog.constraints, key, [])

    %{"live_rows" => live_rows, "seq_scans" => seq_scans, "index_scans" => index_scans} =
      Map.get(catalog.stats, key, @no_stats)

    Table.new(
      prefix: prefix,
      name: name,
      columns: Map.new(columns, &build_column/1),
      indexes: Enum.map(indexes, &build_index/1),
      constraints: Enum.map(constraints, &build_constraint/1),
      live_rows: live_rows,
      seq_scans: seq_scans,
      index_scans: index_scans
    )
  end

  defp build_column(%{
         "column_name" => name,
         "data_type" => data_type,
         "udt_name" => udt_name,
         "character_maximum_length" => max_length,
         "datetime_precision" => precision,
         "is_nullable" => nullable,
         "enum_values" => enum_values
       }) do
    column =
      Column.new(
        name: name,
        type: column_type(data_type, udt_name),
        max_length: max_length,
        precision: precision,
        nullable?: nullable == "YES",
        enum_values: enum_values
      )

    {name, column}
  end

  defp column_type("USER-DEFINED", udt_name), do: udt_name
  defp column_type("ARRAY", _udt_name), do: "array"
  defp column_type(data_type, _udt_name), do: data_type

  defp build_index(%{
         "name" => name,
         "columns" => columns,
         "unique" => unique?,
         "primary" => primary?,
         "partial" => partial?,
         "expression" => expression?,
         "method" => method
       }) do
    Index.new(
      name: name,
      columns: columns,
      unique?: unique?,
      primary?: primary?,
      partial?: partial?,
      expression?: expression?,
      method: method
    )
  end

  defp build_constraint(%{
         "kind" => "f",
         "name" => name,
         "columns" => columns,
         "definition" => definition,
         "ref_prefix" => ref_prefix,
         "ref_table" => ref_table,
         "ref_columns" => ref_columns,
         "on_delete" => on_delete
       }) do
    Constraint.new(
      name: name,
      kind: :foreign_key,
      columns: columns,
      definition: definition,
      references: {ref_prefix, ref_table, ref_columns},
      on_delete: Map.fetch!(@delete_actions, on_delete)
    )
  end

  defp build_constraint(%{
         "name" => name,
         "kind" => kind,
         "columns" => columns,
         "definition" => definition
       }) do
    Constraint.new(
      name: name,
      kind: Map.fetch!(@kinds, kind),
      columns: columns,
      definition: definition
    )
  end

  # pg_stat_statements is an extension so most dev databases don't have it
  defp slow_queries(repo) do
    case rows(repo, "SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'", []) do
      [] -> []
      _found -> repo |> rows(@slow_queries, []) |> Enum.map(&slow_query(repo, &1))
    end
  end

  defp slow_query(repo, %{"query" => query, "calls" => calls, "mean_ms" => mean_ms}) do
    %{query: query, calls: calls, mean_ms: mean_ms, plan: explain(repo, query)}
  end

  # Generic plans need PostgreSQL 16 and work on queries that still have $1 placeholders
  # Planning can still run immutable functions so it happens read only with a timeout and is rolled back
  defp explain(repo, query) do
    {:error, plan} =
      repo.transaction(fn ->
        SQL.query!(repo, "SET TRANSACTION READ ONLY", [], log: false)
        SQL.query!(repo, "SET LOCAL statement_timeout = '2s'", [], log: false)
        repo.rollback(plan(repo, query))
      end)

    plan
  end

  defp plan(repo, query) do
    case SQL.query(repo, "EXPLAIN (GENERIC_PLAN) " <> query, [], log: false) do
      {:ok, %{rows: rows}} -> Enum.map_join(rows, "\n", fn [line] -> line end)
      {:error, _reason} -> nil
    end
  end
end
