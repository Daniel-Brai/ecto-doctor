defmodule EctoDoctor.Checks do
  @moduledoc false

  alias EctoDoctor.Checks.EnumMismatch
  alias EctoDoctor.Checks.MismatchedKeyType
  alias EctoDoctor.Checks.MissingForeignKey
  alias EctoDoctor.Checks.MissingNotNull
  alias EctoDoctor.Checks.OnDeleteMismatch
  alias EctoDoctor.Checks.OrphanTable
  alias EctoDoctor.Checks.RedundantIndex
  alias EctoDoctor.Checks.SequentialScans
  alias EctoDoctor.Checks.SlowQueries
  alias EctoDoctor.Checks.StringLengthOverflow
  alias EctoDoctor.Checks.TypeMismatch
  alias EctoDoctor.Checks.UnhandledConstraint
  alias EctoDoctor.Checks.UnindexedForeignKey
  alias EctoDoctor.Checks.UniqueWithoutIndex
  alias EctoDoctor.Finding
  alias EctoDoctor.Model

  @all [
    UnhandledConstraint,
    StringLengthOverflow,
    EnumMismatch,
    TypeMismatch,
    UniqueWithoutIndex,
    MissingNotNull,
    UnindexedForeignKey,
    MissingForeignKey,
    MismatchedKeyType,
    OnDeleteMismatch,
    RedundantIndex,
    OrphanTable,
    SequentialScans,
    SlowQueries
  ]

  @spec all() :: [module()]
  def all, do: @all

  @spec run(Model.t(), keyword()) :: [Finding.t()]
  def run(%Model{} = model, opts) do
    findings =
      @all
      |> Enum.filter(&enabled?(&1.id(), opts))
      |> Enum.flat_map(fn check -> check.run(model, check_opts(check.id(), opts)) end)

    findings
    |> Enum.reject(&ignored?(&1, model, opts))
    |> Enum.filter(&(Keyword.fetch!(opts, :all) or &1.level != :info))
    |> Enum.sort_by(&sort_key/1)
  end

  defp enabled?(id, opts) do
    cond do
      is_list(opts[:only]) and id not in opts[:only] -> false
      id in Keyword.fetch!(opts, :except) -> false
      true -> opts[:checks][id] != false
    end
  end

  # nil sorts before any file name so findings that point at no file come first
  defp sort_key(finding) do
    {Finding.rank(finding.level), finding.file, finding.line, finding.check}
  end

  defp check_opts(id, opts) do
    case opts[:checks][id] do
      check_opts when is_list(check_opts) -> check_opts
      _other -> []
    end
  end

  defp ignored?(finding, model, opts) do
    targets = targets(finding)

    patterns =
      Keyword.fetch!(opts, :ignore_tables) ++
        Keyword.get(check_opts(finding.check, opts), :ignore, [])

    ignored_by_schema? = finding.check in Map.get(model.ignores, finding.schema, [])

    ignored_by_pattern? =
      Enum.any?(patterns, fn pattern -> Enum.any?(targets, &glob?(pattern, &1)) end)

    ignored_by_schema? or ignored_by_pattern?
  end

  # A finding about no table, such as a slow query, has nothing to match a table pattern
  defp targets(%Finding{table: nil}), do: []

  defp targets(finding),
    do: [finding.table | Enum.map(finding.columns, &"#{finding.table}.#{&1}")]

  # ab*b can't match ab since the start and the end can't share letters
  defp long_enough?(value, head, tail), do: byte_size(value) >= byte_size(head) + byte_size(tail)

  defp glob?(pattern, value) do
    case String.split(pattern, "*", parts: 2) do
      [exact] ->
        value == exact

      [head, tail] ->
        long_enough?(value, head, tail) and String.starts_with?(value, head) and
          String.ends_with?(value, tail)
    end
  end
end
