defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
    :ok
  end
end
