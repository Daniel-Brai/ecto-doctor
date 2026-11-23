defmodule EctoDoctor.RepeatedQueries.AssertionsTest do
  use EctoDoctor.DataCase, async: true

  import EctoDoctor.RepeatedQueries.Assertions

  alias EctoDoctor.Test.Feed
  alias EctoDoctor.TestUtils

  setup do
    user = TestUtils.insert_random_user!()
    %{posts: TestUtils.insert_random_posts!(user, 3)}
  end

  describe "assert_no_repeated_queries/1" do
    test "fails on an N+1 query", %{posts: posts} do
      assert_raise ExUnit.AssertionError, fn ->
        assert_no_repeated_queries(fn -> Feed.authors(posts) end)
      end
    end
  end

  describe "assert_repeated_queries/1" do
    test "fails without an N+1 query", %{posts: posts} do
      assert_raise ExUnit.AssertionError, fn ->
        assert_repeated_queries(fn -> Feed.preloaded_authors(posts) end)
      end
    end
  end
end
