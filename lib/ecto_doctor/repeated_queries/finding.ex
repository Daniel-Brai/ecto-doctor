defmodule EctoDoctor.RepeatedQueries.Finding do
  @moduledoc """
  Describes one N+1 query.
  The same query ran `count` times from the same call stack in one unit of work.

  The `:origin` is the first frame in your own code outside the repo, which is usually the line to change.

  The `:key` is what the baseline file stores.
  It leaves out line numbers so editing the code around a known N+1 doesn't make it new again.
  """

  @type frame :: {module(), atom(), arity(), String.t(), nil | pos_integer()}

  @type t :: %__MODULE__{
          sql: String.t(),
          count: pos_integer(),
          duration_ms: float(),
          frames: [frame()],
          origin: nil | frame(),
          label: nil | String.t(),
          fix: nil | String.t(),
          key: String.t()
        }

  @enforce_keys [:sql, :count, :duration_ms, :frames, :key]
  defstruct [:sql, :count, :duration_ms, :frames, :origin, :label, :fix, :key]
end
