defmodule Mix.Tasks.Ecto.DoctorTest do
  use EctoDoctor.DataCase, async: false

  alias Mix.Tasks.Ecto.Doctor

  @moduletag :tmp_dir

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  describe "run/1" do
    test "fails on a check name it doesn't know" do
      assert_raise Mix.Error, ~r/Unknown check unhandled_constrant/, fn ->
        Doctor.run(["--only", "unhandled_constrant"])
      end
    end

    test "exits with status 1 when it finds an error" do
      assert catch_exit(Doctor.run(["--no-baseline"])) == {:shutdown, 1}
    end

    test "fails when --fix asks for JSON" do
      assert_raise Mix.Error, ~r/text format only/, fn -> Doctor.run(["--fix", "--format", "json"]) end
    end

    test "reads its options from the config file", %{tmp_dir: dir} do
      config = Path.join(dir, "ecto_doctor.exs")
      File.write!(config, "[only: [:slow_queries]]")

      Doctor.run(["--config", config, "--no-baseline"])
      assert_received {:mix_shell, :info, ["No problems found.\n"]}
    end

    test "fails on an option the config file misspells", %{tmp_dir: dir} do
      config = Path.join(dir, "ecto_doctor.exs")
      File.write!(config, ~s([ignore_table: ["comments"]]))

      assert_raise Mix.Error, ~r/unknown options \[:ignore_table\]/, fn ->
        Doctor.run(["--config", config])
      end
    end

    test "passes when the checks find nothing" do
      Doctor.run(["--only", "slow_queries", "--no-baseline"])
      assert_received {:mix_shell, :info, ["No problems found.\n"]}
    end
  end
end
