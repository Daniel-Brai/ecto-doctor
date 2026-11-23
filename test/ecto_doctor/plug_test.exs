defmodule EctoDoctor.PlugTest do
  use EctoDoctor.DataCase, async: true

  import Plug.Conn
  import Plug.Test

  alias EctoDoctor.Test.Feed
  alias EctoDoctor.TestUtils

  setup do
    user = TestUtils.insert_random_user!()
    {:ok, posts: TestUtils.insert_random_posts!(user, 3)}
  end

  describe "call/2" do
    test "leaves a page with no repeats alone" do
      conn = :get |> conn("/") |> EctoDoctor.Plug.call([])
      conn = conn |> put_resp_content_type("text/html") |> send_resp(200, "<body></body>")

      assert conn.resp_body == "<body></body>"
    end

    test "adds a footer listing the repeats", %{posts: posts} do
      conn = :get |> conn("/posts") |> EctoDoctor.Plug.call([])
      _authors = Feed.authors(posts)
      conn = conn |> put_resp_content_type("text/html") |> send_resp(200, "<body></body>")

      assert String.contains?(conn.resp_body, "1 N+1 query")
    end
  end
end
