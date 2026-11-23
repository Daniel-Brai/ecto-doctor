defmodule EctoDoctor.Checks.SlowQueries do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Finding

  @min_ms 100

  @impl EctoDoctor.Check
  def id, do: :slow_queries

  @impl EctoDoctor.Check
  def explain do
    """
    A query that takes 100 ms or more on average.
    Its plan comes with it.

    It needs the pg_stat_statements extension and only reads queries your own database role ran.
    Change the limit with `min_ms: 500` in this check's options.
    Plans need PostgreSQL 16 or later.
    A plan that shows a Seq Scan usually points at a missing index.
    """
  end

  @impl EctoDoctor.Check
  def run(model, opts) do
    min_ms = Keyword.get(opts, :min_ms, @min_ms)

    for query <- model.database.slow_queries, query.mean_ms >= min_ms do
      %Finding{
        check: id(),
        level: :info,
        message:
          "This query takes #{round(query.mean_ms)} ms on average over #{query.calls} calls. #{query.query}",
        query: query.query,
        fix: query.plan
      }
    end
  end
end
