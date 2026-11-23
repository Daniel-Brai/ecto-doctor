defmodule EctoDoctor.RepeatedQueries.Store do
  @moduledoc false

  alias EctoDoctor.RepeatedQueries.Finding
  alias EctoDoctor.RepeatedQueries.Query
  alias EctoDoctor.RepeatedQueries.Watcher

  @scans :ecto_doctor_scans
  @queries :ecto_doctor_queries
  @units :ecto_doctor_units
  @recorded :ecto_doctor_recorded
  @flags :ecto_doctor_flags

  # Positions in a scan row {owner, label, depth, paused, watched?, count}
  @depth 3
  @paused 4
  @count 6

  # A real N+1 shows long before this so a scan stops here instead of growing without end
  @max_queries 100_000

  @doc "Creates the tables in the calling process, which owns them for as long as it lives."
  @spec create_tables() :: :ok
  def create_tables do
    @scans = :ets.new(@scans, [:named_table, :public, read_concurrency: true])

    @queries =
      :ets.new(@queries, [:named_table, :public, :duplicate_bag, write_concurrency: true])

    @units = :ets.new(@units, [:named_table, :public, read_concurrency: true])
    @recorded = :ets.new(@recorded, [:named_table, :public, write_concurrency: true])
    @flags = :ets.new(@flags, [:named_table, :public])
    :ok
  end

  @doc "Drops everything a dead process left behind."
  @spec drop(pid()) :: true
  def drop(pid) do
    :ets.delete(@scans, pid)
    :ets.delete(@queries, pid)
    :ets.delete(@units, pid)
  end

  @doc "Returns true only the first time it's called for a kind of warning while the tables live."
  @spec first_warning?(atom()) :: boolean()
  def first_warning?(kind), do: ready?() and :ets.insert_new(@flags, {kind})

  @spec record([String.t()]) :: true
  def record(keys), do: :ets.insert(@recorded, Enum.map(keys, &{&1}))

  @spec recorded() :: [String.t()]
  def recorded, do: @recorded |> :ets.tab2list() |> Enum.map(fn {key} -> key end)

  @doc """
  Finds the process whose scan this process's queries go into.

  A task that a test starts adds its queries to the test's scan.
  Elixir lists the processes that started a task under the $callers key, the same list the Ecto sandbox uses to share a connection.
  """
  @spec owner() :: nil | pid()
  def owner do
    if ready?() do
      Enum.find(self_and_callers(), &:ets.member(@scans, &1))
    end
  end

  defp self_and_callers, do: [self() | Process.get(:"$callers", [])]

  @doc "Starts a scan or nests inside the one this process already belongs to."
  @spec start(nil | String.t()) :: pid()
  def start(label), do: start(label, false)

  @doc """
  Starts a scan that is dropped if its process dies before finishing it.

  Requests and jobs can die halfway.
  A test scan isn't watched because ExUnit finishes it in on_exit after the test process is gone.
  """
  @spec start_watched(nil | String.t()) :: pid()
  def start_watched(label), do: start(label, true)

  defp start(label, watched?) do
    case owner() do
      nil ->
        :ets.insert(@scans, {self(), label, 0, 0, watched?, 0})
        if watched?, do: Watcher.watch(self())
        self()

      owner ->
        :ets.update_counter(@scans, owner, {@depth, 1})
        owner
    end
  end

  @doc "Ends one level of a scan and returns its label and queries once the outermost level ends."
  @spec finish(pid()) :: nil | {nil | String.t(), list()}
  def finish(owner) do
    case :ets.lookup(@scans, owner) do
      [{^owner, _label, 0, _paused, _watched?, _count}] ->
        close(owner)

      [{^owner, _label, _depth, _paused, _watched?, _count}] ->
        :ets.update_counter(@scans, owner, {@depth, -1})
        nil

      [] ->
        nil
    end
  end

  @doc "Ends a scan however deeply it is nested, such as a test whose request raised halfway."
  @spec close(pid()) :: nil | {nil | String.t(), list()}
  def close(owner) do
    case :ets.take(@scans, owner) do
      [{^owner, label, _depth, _paused, _watched?, _count}] -> {label, :ets.take(@queries, owner)}
      [] -> nil
    end
  end

  @doc """
  Drops a watched scan this process left open, such as one from a request that raised.

  A test scan stays so a request made inside a test nests in it.
  """
  @spec reset(pid()) :: :ok
  def reset(pid) do
    :ets.delete(@units, pid)

    case :ets.lookup(@scans, pid) do
      [{^pid, _label, _depth, _paused, true, _count}] -> close(pid)
      _not_watched -> nil
    end

    :ok
  end

  @doc "Checks whether the tables exist, since they go away when the Watcher stops."
  @spec ready?() :: boolean()
  def ready?, do: :ets.whereis(@scans) != :undefined

  @spec max_queries() :: pos_integer()
  def max_queries, do: @max_queries

  @doc "Adds a query to the scan, returns :full once the scan holds as many as it keeps and :closed after it ends."
  @spec add(pid(), map()) :: :ok | :full | :closed
  def add(owner, query) do
    if count(owner) <= @max_queries do
      :ets.insert(@queries, {owner, System.unique_integer([:monotonic]), query})
      :ok
    else
      :full
    end
  rescue
    ArgumentError -> :closed
  end

  # The scan can end between the check that it is open and this update and ETS can't skip a missing row
  defp count(owner), do: :ets.update_counter(@scans, owner, {@count, 1})

  @doc """
  Marks the start of a request, LiveView callback or job in this process.

  Queries from two units never add up to an N+1 even inside one test.
  A LiveView mounts twice for example, once for the static page and once connected.
  """
  @spec enter_unit() :: true
  def enter_unit, do: :ets.insert(@units, {self(), [make_ref() | units(self())]})

  @spec leave_unit() :: true
  def leave_unit do
    case units(self()) do
      [_unit] -> :ets.delete(@units, self())
      [_unit | outer] -> :ets.insert(@units, {self(), outer})
      [] -> true
    end
  end

  @doc "Returns the request, LiveView callback or job running in this process."
  @spec unit() :: nil | reference()
  def unit, do: List.first(units(self()))

  defp units(pid) do
    case :ets.lookup(@units, pid) do
      [{^pid, units}] -> units
      [] -> []
    end
  end

  @doc """
  Takes the queries added after `mark` so a block can be checked on its own.

  Queries are taken one by one so a query another process adds meanwhile is kept.
  """
  @spec take_after(pid(), integer()) :: list()
  def take_after(owner, mark) do
    later = Enum.filter(queries(owner), fn {_owner, sequence, _query} -> sequence > mark end)

    Enum.each(later, &:ets.delete_object(@queries, &1))
    later
  end

  @spec queries(pid()) :: list()
  def queries(owner), do: :ets.lookup(@queries, owner)

  @doc "Checks whether queries still count toward the scan since it may be paused or closed."
  @spec counting?(pid()) :: boolean()
  def counting?(owner) do
    case :ets.lookup(@scans, owner) do
      [{^owner, _label, _depth, paused, _watched?, _count}] -> paused == 0
      [] -> false
    end
  end

  @doc "Checks whether the scan is open since its code may have closed it or its owner died."
  @spec open?(pid()) :: boolean()
  def open?(owner), do: :ets.member(@scans, owner)

  @spec pause(pid()) :: integer()
  def pause(owner), do: :ets.update_counter(@scans, owner, {@paused, 1})

  @spec resume(pid()) :: integer()
  def resume(owner), do: :ets.update_counter(@scans, owner, {@paused, -1})

  @doc "Turns the queries of one scan into findings."
  @spec findings(list(), map(), nil | String.t()) :: [Finding.t()]
  def findings(rows, config, label) do
    rows
    |> Enum.map(fn {_owner, _seq, query} -> query end)
    |> Enum.group_by(&{&1.sql, &1.frames, &1.unit})
    |> Enum.filter(fn {_key, group} -> length(group) >= config.threshold end)
    |> Enum.map(fn {_key, group} -> finding(group, config, label) end)
    |> Enum.filter(&(&1.duration_ms >= config.min_duration_ms))
    |> Enum.reject(&skipped?(&1, config))
  end

  defp finding([first | _rest] = group, config, label) do
    microseconds = group |> Enum.map(& &1.microseconds) |> Enum.sum()

    calls =
      Enum.map(first.frames, fn {module, fun, arity, _file, _line} -> {module, fun, arity} end)

    %Finding{
      sql: first.sql,
      count: length(group),
      duration_ms: microseconds / 1000,
      frames: first.frames,
      origin:
        Enum.find(first.frames, fn {module, _fun, _arity, _file, _line} ->
          module not in config.repos
        end),
      label: label,
      fix: Query.fix(first.sql, first.source, config.schemas),
      key: Integer.to_string(:erlang.phash2({first.sql, calls}, 4_294_967_296), 36)
    }
  end

  defp skipped?(finding, config) do
    files = Enum.map(finding.frames, fn {_module, _fun, _arity, file, _line} -> file end)

    ignored? = Enum.any?(config.ignore_queries, &String.contains?(finding.sql, &1))
    out_of_focus? = config.focus != [] and not in_paths?(files, config.focus)
    ignored? or in_paths?(files, config.allow) or out_of_focus?
  end

  defp in_paths?(files, paths) do
    Enum.any?(paths, fn path -> Enum.any?(files, &String.contains?(&1, path)) end)
  end
end
