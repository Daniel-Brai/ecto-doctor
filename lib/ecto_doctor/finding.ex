defmodule EctoDoctor.Finding do
  @moduledoc """
  Describes one problem a check found.

  The `:fix` field holds the code change to make, or the plan for a slow query.
  The `:query` field holds the SQL a slow query finding is about.
  The `:migration` field holds the migration steps that fix it and the phase each one runs in.

  Concurrent index changes run on their own and new constraints are validated in a later migration.
  """

  @type level :: :error | :warning | :info

  @type phase :: :concurrent | :add | :validate

  @type t :: %__MODULE__{
          check: atom(),
          level: level(),
          message: String.t(),
          fix: nil | String.t(),
          migration: [{phase(), String.t()}],
          schema: nil | module(),
          file: nil | String.t(),
          line: nil | pos_integer(),
          table: nil | String.t(),
          columns: [String.t()],
          query: nil | String.t()
        }

  @enforce_keys [:check, :level, :message]
  defstruct [
    :check,
    :level,
    :message,
    :fix,
    :schema,
    :file,
    :line,
    :table,
    :query,
    columns: [],
    migration: []
  ]

  @levels [:error, :warning, :info]

  @doc "Returns a level's rank where 0 is the most severe."
  @spec rank(level()) :: non_neg_integer()
  def rank(level), do: Enum.find_index(@levels, &(&1 == level))

  @doc """
  Returns the stable key the baseline file keeps for a finding.

  It leaves out the message and line so a finding that moves still matches.
  """
  @spec key(t()) :: String.t()
  def key(%__MODULE__{query: nil} = finding) do
    Enum.join([finding.check, finding.table, Enum.join(finding.columns, ",")], ":")
  end

  # A slow query has no table so its SQL tells one apart from another
  def key(%__MODULE__{} = finding) do
    key(%{finding | query: nil}) <>
      ":" <> Integer.to_string(:erlang.phash2(finding.query, 4_294_967_296), 36)
  end
end
