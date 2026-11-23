defmodule Mix.Tasks.Ecto.Doctor.ExplainTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Ecto.Doctor.Explain

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  describe "run/1" do
    test "fails on a check name it doesn't know" do
      assert_raise Mix.Error, ~r/no check named nope/, fn -> Explain.run(["nope"]) end
    end
  end
end
