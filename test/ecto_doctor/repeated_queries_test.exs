defmodule EctoDoctor.RepeatedQueriesTest do
  use EctoDoctor.DataCase, async: true

  alias EctoDoctor.RepeatedQueries
  alias EctoDoctor.RepeatedQueries.Query
  alias EctoDoctor.RepeatedQueries.Store
  alias EctoDoctor.Schema
  alias EctoDoctor.Test.Comment
  alias EctoDoctor.Test.Feed
  alias EctoDoctor.TestUtils

  setup do
    user = TestUtils.insert_random_user!()
    {:ok, posts: TestUtils.insert_random_posts!(user, 3)}
  end

  describe "findings/1" do
    test "returns nothing for a preload", %{posts: posts} do
      assert RepeatedQueries.findings(fn -> Feed.preloaded_authors(posts) end) == []
    end

    test "returns nothing for inserts in a loop" do
      assert RepeatedQueries.findings(fn ->
               Enum.each(1..3, fn _ -> TestUtils.insert_random_user!() end)
             end) == []
    end

    test "returns nothing for paused code", %{posts: posts} do
      assert RepeatedQueries.findings(fn ->
               RepeatedQueries.pause(fn -> Feed.authors(posts) end)
             end) == []
    end

    test "finds a query run in a loop", %{posts: posts} do
      [finding] = RepeatedQueries.findings(fn -> Feed.authors(posts) end)
      assert finding.count == 3
    end

    test "finds a query run in a task the code started", %{posts: posts} do
      [finding] =
        RepeatedQueries.findings(fn ->
          fn -> Feed.authors(posts) end |> Task.async() |> Task.await()
        end)

      assert finding.count == 3
    end

    test "finds a query run in a request made inside it", %{posts: posts} do
      conn = Plug.Test.conn(:get, "/feed")

      [finding] =
        RepeatedQueries.findings(fn ->
          :telemetry.execute([:phoenix, :endpoint, :start], %{}, %{conn: conn})
          Feed.authors(posts)
          :telemetry.execute([:phoenix, :endpoint, :stop], %{}, %{conn: conn})
        end)

      assert finding.count == 3
    end

    test "keeps the queries of two LiveView mounts apart", %{posts: posts} do
      metadata = %{socket: %{view: Feed}}

      mount = fn ->
        :telemetry.execute([:phoenix, :live_view, :mount, :start], %{}, metadata)
        Feed.authors([hd(posts)])
        :telemetry.execute([:phoenix, :live_view, :mount, :stop], %{}, metadata)
      end

      assert RepeatedQueries.findings(fn -> Enum.each(1..2, fn _ -> mount.() end) end) == []
    end

    test "points at the app code that ran it", %{posts: posts} do
      [finding] = RepeatedQueries.findings(fn -> Feed.authors(posts) end)
      {module, _fun, _arity, _file, _line} = finding.origin

      assert module == Feed
    end

    test "suggests the association to preload", %{posts: posts} do
      [finding] = RepeatedQueries.findings(fn -> Feed.comments(posts) end)

      assert finding.fix ==
               "Preload :comments on EctoDoctor.Test.Post where the parent rows are loaded."
    end

    test "suggests the association for a preload run in a loop", %{posts: posts} do
      [finding] = RepeatedQueries.findings(fn -> Feed.comments_one_by_one(posts) end)
      assert finding.fix =~ "Preload :comments"
    end

    test "suggests the association from a MySQL query" do
      sql = "SELECT p0.`id` FROM `posts` AS p0 WHERE (p0.`id` = ?)"
      assert Query.fix(sql, "posts", [Schema.from_module(Comment)]) =~ "Preload :post"
    end

    test "suggests the association from a SQLite query" do
      sql = ~s[SELECT p0."id" FROM "posts" AS p0 WHERE (p0."id" = ?)]
      assert Query.fix(sql, "posts", [Schema.from_module(Comment)]) =~ "Preload :post"
    end

    test "gives general advice when several associations fit", %{posts: posts} do
      [finding] = RepeatedQueries.findings(fn -> Feed.authors(posts) end)
      assert String.starts_with?(finding.fix, "Load these users rows in one query")
    end
  end

  describe "scan/2" do
    test "ends its scan when the function raises" do
      catch_error(RepeatedQueries.scan(fn -> raise "boom" end))
      assert Store.owner() == nil
    end
  end

  describe "a test scan" do
    test "outlives the test process so on_exit can report it", %{posts: posts} do
      task =
        Task.async(fn ->
          owner = Store.start("test")
          Feed.authors(posts)
          owner
        end)

      owner = Task.await(task)
      ref = Process.monitor(owner)
      assert_receive {:DOWN, ^ref, :process, ^owner, _reason}

      {"test", queries} = Store.close(owner)
      assert length(queries) == 3
    end
  end
end
