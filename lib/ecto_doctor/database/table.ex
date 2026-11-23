defmodule EctoDoctor.Database.Table do
  @moduledoc false

  alias EctoDoctor.Database.Column
  alias EctoDoctor.Database.Constraint
  alias EctoDoctor.Database.Index

  @type t :: %__MODULE__{
          prefix: nil | String.t(),
          name: String.t(),
          columns: %{String.t() => Column.t()},
          indexes: [Index.t()],
          constraints: [Constraint.t()],
          live_rows: non_neg_integer(),
          seq_scans: non_neg_integer(),
          index_scans: non_neg_integer()
        }

  @enforce_keys [:prefix, :name]
  defstruct [
    :prefix,
    :name,
    columns: %{},
    indexes: [],
    constraints: [],
    live_rows: 0,
    seq_scans: 0,
    index_scans: 0
  ]

  @spec new(keyword()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)
end
