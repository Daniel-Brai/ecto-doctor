defmodule EctoDoctor.RepeatedQueries.Error do
  @moduledoc "Fails a test at its end when it ran a new N+1 query."

  @type t :: %__MODULE__{message: String.t()}

  defexception [:message]
end
