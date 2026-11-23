defmodule EctoDoctor.BaselineTest do
  use ExUnit.Case, async: true

  alias EctoDoctor.Baseline
  alias EctoDoctor.Error

  @moduletag :tmp_dir

  @empty %{findings: [], repeated_queries: []}

  # Running this file would raise so loading it proves the baseline is only read
  @unsafe ~S|%{findings: ["abc", raise("evaluated")], repeated_queries: raise("evaluated")}|

  setup %{tmp_dir: dir} do
    {:ok, path: Path.join(dir, "baseline.exs")}
  end

  describe "load/1" do
    test "fails if the file isn't a baseline map", %{path: path} do
      File.write!(path, "[:not, :a, :map]")
      assert {:error, %Error{}} = Baseline.load(path)
    end

    test "reads only lists of strings and never runs the file", %{path: path} do
      File.write!(path, @unsafe)
      assert Baseline.load(path) == {:ok, %{@empty | findings: ["abc"]}}
    end

    test "treats a missing file as empty", %{path: path} do
      assert Baseline.load(path) == {:ok, @empty}
    end
  end

  describe "write/3" do
    test "keeps the other section", %{path: path} do
      Baseline.write(path, :findings, ["b", "a"])
      Baseline.write(path, :repeated_queries, ["x"])

      assert Baseline.read!(path) == %{findings: ["a", "b"], repeated_queries: ["x"]}
    end
  end
end
