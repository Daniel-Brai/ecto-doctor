defmodule EctoDoctor.RepeatedQueries.Assertions do
  @moduledoc """
  Checks one block of code for N+1 queries inside an ExUnit test.

      import EctoDoctor.RepeatedQueries.Assertions

      test "lists posts", %{conn: conn} do
        assert_no_repeated_queries(fn -> get(conn, ~p"/posts") end)
      end

  The block is scanned on its own so its queries don't count toward the test's own scan.
  """

  alias EctoDoctor.RepeatedQueries
  alias EctoDoctor.RepeatedQueries.Report

  @doc "Fails the test when the function runs an N+1 query and shows where it came from."
  @spec assert_no_repeated_queries((-> term())) :: :ok
  def assert_no_repeated_queries(fun) do
    case RepeatedQueries.findings(fun) do
      [] ->
        :ok

      findings ->
        message = Enum.map_join(findings, "\n\n", &Report.format/1)

        raise ExUnit.AssertionError,
          message: "Expected no N+1 queries but found these.\n\n" <> message
    end
  end

  @doc "Fails the test when the function runs no N+1 query, such as to prove the old code is still caught."
  @spec assert_repeated_queries((-> term())) :: :ok
  def assert_repeated_queries(fun) do
    if RepeatedQueries.findings(fun) == [] do
      raise ExUnit.AssertionError, message: "Expected an N+1 query but found none."
    end

    :ok
  end
end
