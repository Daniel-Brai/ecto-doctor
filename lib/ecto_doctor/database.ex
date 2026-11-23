defmodule EctoDoctor.Database do
  @moduledoc false

  alias EctoDoctor.Database.Table

  @type slow_query :: %{
          query: String.t(),
          calls: non_neg_integer(),
          mean_ms: float(),
          plan: nil | String.t()
        }

  @type t :: %__MODULE__{
          adapter: module(),
          default_prefix: nil | String.t(),
          tables: %{{nil | String.t(), String.t()} => Table.t()},
          slow_queries: [slow_query()]
        }

  @enforce_keys [:adapter]
  defstruct [:adapter, :default_prefix, tables: %{}, slow_queries: []]

  @spec new(keyword()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)

  @spec table(t(), nil | String.t(), String.t()) :: nil | Table.t()
  def table(%__MODULE__{} = database, prefix, name) do
    database.tables[{prefix || database.default_prefix, name}]
  end
end
