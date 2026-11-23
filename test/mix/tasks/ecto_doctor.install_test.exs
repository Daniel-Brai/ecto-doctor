defmodule Mix.Tasks.EctoDoctor.InstallTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.EctoDoctor.Install

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    File.cp_r!("test/fixtures/install", dir)
    File.cd!(dir, fn -> Install.run([]) end)
    :ok
  end

  describe "run/1" do
    test "scans every test from the data case", %{tmp_dir: dir} do
      assert File.read!(Path.join(dir, "test/support/data_case.ex")) =~
               "setup tags do\n    :ok = EctoDoctor.RepeatedQueries.scan_test(tags)"
    end

    test "adds nothing the second time", %{tmp_dir: dir} do
      once = File.read!(Path.join(dir, "test/test_helper.exs"))
      File.cd!(dir, fn -> Install.run([]) end)

      assert File.read!(Path.join(dir, "test/test_helper.exs")) == once
    end
  end
end
