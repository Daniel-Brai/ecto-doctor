defmodule EctoDoctor.Rule do
  @moduledoc false

  @type kind ::
          :cast
          | :validate_required
          | :validate_length
          | :unique_constraint
          | :foreign_key_constraint
          | :assoc_constraint
          | :check_constraint
          | :exclusion_constraint

  @type t :: %__MODULE__{
          kind: kind(),
          fields: :unknown | [atom()],
          opts: keyword(),
          module: module(),
          struct: nil | module(),
          schema: nil | module(),
          file: String.t(),
          line: nil | pos_integer()
        }

  @enforce_keys [:kind, :fields, :module, :file]
  defstruct [:kind, :fields, :module, :struct, :schema, :file, :line, opts: []]

  @kinds ~w[
    cast
    validate_required
    validate_length
    unique_constraint
    foreign_key_constraint
    assoc_constraint
    check_constraint
    exclusion_constraint
  ]a

  @spec kinds() :: [kind()]
  def kinds, do: @kinds
end
