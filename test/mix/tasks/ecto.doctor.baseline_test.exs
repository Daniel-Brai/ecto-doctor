defmodule Mix.Tasks.Ecto.Doctor.BaselineTest do
  use EctoDoctor.DataCase, async: false

  alias EctoDoctor.Baseline
  alias Mix.Tasks.Ecto.Doctor.Baseline, as: BaselineTask

  @moduletag :tmp_dir

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  describe "run/1" do
    test "fails when the config turns the baseline off", %{tmp_dir: dir} do
      config = Path.join(dir, "ecto_doctor.exs")
      File.write!(config, "[baseline: nil]")

      assert_raise Mix.Error, ~r/baseline: nil/, fn -> BaselineTask.run(["--config", config]) end
    end

    test "writes every current finding", %{tmp_dir: dir} do
      config = Path.join(dir, "ecto_doctor.exs")
      path = Path.join(dir, "baseline.exs")
      File.write!(config, "[baseline: #{inspect(path)}]")
      BaselineTask.run(["--config", config])

      assert Baseline.read!(path).findings != []
    end
  end
end
