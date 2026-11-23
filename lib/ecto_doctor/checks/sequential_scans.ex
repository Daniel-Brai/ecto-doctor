defmodule EctoDoctor.Checks.SequentialScans do
  @moduledoc false

  @behaviour EctoDoctor.Check

  alias EctoDoctor.Check
  alias EctoDoctor.Finding

  @min_rows 10_000

  @impl EctoDoctor.Check
  def id, do: :sequential_scans

  @impl EctoDoctor.Check
  def explain do
    """
    A large table read more often by sequential scans than through indexes.

    It reads PostgreSQL's table statistics so it only means something on a database with real traffic like a production replica.
    It skips tables under 10,000 rows.
    Change that with `min_rows: 50_000` in this check's options.
    """
  end

  @impl EctoDoctor.Check
  def run(model, opts) do
    min_rows = Keyword.get(opts, :min_rows, @min_rows)

    for table <- Map.values(model.database.tables), scanned_mostly?(table, min_rows) do
      finding(model, table)
    end
  end

  defp scanned_mostly?(table, min_rows) do
    table.live_rows >= min_rows and table.seq_scans > table.index_scans
  end

  defp finding(model, table) do
    table_name = Check.table_name(model, table)

    %Finding{
      check: id(),
      level: :info,
      table: table_name,
      message:
        "#{table_name} has #{table.live_rows} rows. Sequential scans read it #{table.seq_scans} times against #{table.index_scans} through indexes."
    }
  end
end
