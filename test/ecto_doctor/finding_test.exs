defmodule EctoDoctor.FindingTest do
  use ExUnit.Case, async: true

  alias EctoDoctor.Finding

  describe "key/1" do
    test "gives each slow query its own key" do
      slow = %Finding{check: :slow_queries, level: :info, message: "Slow.", query: "SELECT 1"}
      refute Finding.key(slow) == Finding.key(%{slow | query: "SELECT 2"})
    end
  end
end
