defmodule EctoDoctor.Database.Index do
  @moduledoc false

  @type t :: %__MODULE__{
          name: String.t(),
          columns: [String.t()],
          unique?: boolean(),
          primary?: boolean(),
          partial?: boolean(),
          expression?: boolean(),
          method: String.t()
        }

  @fields ~w[name columns unique? primary? partial? expression? method]a

  @enforce_keys @fields
  defstruct @fields

  @spec new(keyword()) :: t()
  def new(fields), do: struct!(__MODULE__, fields)
end
