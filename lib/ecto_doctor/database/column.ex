defmodule EctoDoctor.Database.Column do
  @moduledoc false

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t(),
          max_length: nil | pos_integer(),
          precision: nil | non_neg_integer(),
          nullable?: boolean(),
          enum_values: nil | [String.t()]
        }

  @fields ~w[name type max_length precision nullable? enum_values]a

  @enforce_keys @fields
  defstruct @fields

  @spec new(keyword()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)
end
