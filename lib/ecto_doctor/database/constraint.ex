defmodule EctoDoctor.Database.Constraint do
  @moduledoc false

  @type kind :: :unique | :foreign_key | :check | :exclusion

  @type t :: %__MODULE__{
          name: String.t(),
          kind: kind(),
          columns: [String.t()],
          references: nil | {nil | String.t(), String.t(), [String.t()]},
          on_delete: nil | String.t(),
          definition: nil | String.t()
        }

  @enforce_keys [:name, :kind]
  defstruct [:name, :kind, :references, :on_delete, :definition, columns: []]

  @spec new(keyword()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)
end
