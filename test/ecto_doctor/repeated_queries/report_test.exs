defmodule EctoDoctor.RepeatedQueries.ReportTest do
  use EctoDoctor.DataCase, async: true

  alias EctoDoctor.RepeatedQueries
  alias EctoDoctor.RepeatedQueries.Error
  alias EctoDoctor.RepeatedQueries.Report
  alias EctoDoctor.Test.Feed
  alias EctoDoctor.TestUtils

  @moduletag :tmp_dir

  @config %{
    known: MapSet.new(),
    strict?: false,
    log: false,
    github_annotations: false,
    json_report: nil
  }

  setup do
    user = TestUtils.insert_random_user!()
    posts = TestUtils.insert_random_posts!(user, 3)
    %{findings: RepeatedQueries.findings(fn -> Feed.authors(posts) end)}
  end

  describe "report!/2" do
    test "raises on a new N+1 once the app has a baseline", %{findings: findings} do
      assert_raise Error, fn -> Report.report!(findings, %{@config | strict?: true}) end
    end

    test "returns a new N+1 before the app has a baseline", %{findings: findings} do
      assert Report.report!(findings, @config) == findings
    end

    test "leaves out an N+1 the baseline knows", %{findings: [finding]} do
      config = %{@config | known: MapSet.new([finding.key]), strict?: true}
      assert Report.report!([finding], config) == []
    end
  end

  describe "report/2" do
    test "appends each N+1 to the JSON report", %{findings: findings, tmp_dir: dir} do
      path = Path.join(dir, "n_plus_one.jsonl")
      Report.report(findings, %{@config | json_report: path})

      assert %{"origin" => %{"call" => "EctoDoctor.Test.Feed.authors/1"}} =
               path |> File.read!() |> JSON.decode!()
    end
  end
end
