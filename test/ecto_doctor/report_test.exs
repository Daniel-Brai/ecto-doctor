defmodule EctoDoctor.ReportTest do
  use ExUnit.Case, async: true

  alias EctoDoctor.Finding
  alias EctoDoctor.Report.GitHub
  alias EctoDoctor.Report.SARIF
  alias EctoDoctor.Report.Text

  @finding %Finding{
    check: :missing_not_null,
    level: :warning,
    message: "name is required in a changeset but the column allows NULL.",
    file: "lib/user.ex",
    line: 4,
    table: "users",
    columns: ["name"]
  }

  describe "Text.format/1" do
    test "keeps a name from the database from starting a GitHub command" do
      finding = %{@finding | message: "evil\n::error::x\e[31m has no schema."}
      refute String.contains?(Text.format([finding]), ["\n::", "\e"])
    end
  end

  describe "SARIF.format/1" do
    test "puts each finding on its line" do
      %{"runs" => [%{"results" => [result]}]} = [@finding] |> SARIF.format() |> JSON.decode!()
      [%{"physicalLocation" => %{"region" => region}}] = result["locations"]

      assert region["startLine"] == 4
    end
  end

  describe "GitHub.format/1" do
    test "keeps a message on one line so it can't start a new command" do
      finding = %{@finding | message: "evil\n::error::x"}

      assert [_one_line] =
               finding |> List.wrap() |> GitHub.format() |> String.split("\n", trim: true)
    end
  end
end
