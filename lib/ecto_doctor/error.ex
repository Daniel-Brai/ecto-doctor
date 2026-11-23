defmodule EctoDoctor.Error do
  @moduledoc "Explains why Ecto Doctor can't run when a function returns it or raises it."

  @type t :: %__MODULE__{message: String.t()}

  defexception [:message]
end
