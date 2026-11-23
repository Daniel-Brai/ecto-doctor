defmodule EctoDoctor.RepeatedQueries do
  @schema NimbleOptions.new!(
            repo: [
              type: {:or, [:atom, {:list, :atom}]},
              required: true,
              doc: "Names the repo to watch or a list of repos."
            ],
            threshold: [
              type: :pos_integer,
              default: 2,
              doc: "Sets how many identical queries make an N+1."
            ],
            mode: [
              type: {:in, [:raise, :warn]},
              default: :raise,
              doc: "Chooses whether a test with a new N+1 fails or only prints it."
            ],
            baseline: [
              type: {:or, [:string, nil]},
              default: EctoDoctor.Baseline.default_path(),
              doc: "Leaves out the N+1 queries listed in this file."
            ],
            apps: [
              type: {:list, :atom},
              doc: "Picks the apps whose code counts in call stacks. Defaults to the repos' apps."
            ],
            allow: [
              type: {:list, :string},
              default: [],
              doc: "Ignores N+1 queries whose call stack has a file path containing one of these."
            ],
            focus: [
              type: {:list, :string},
              default: [],
              doc:
                "Reports only N+1 queries whose call stack has a file path containing one of these."
            ],
            ignore_queries: [
              type: {:list, :string},
              default: [],
              doc: "Ignores queries whose SQL contains one of these."
            ],
            ignore_frames: [
              type: {:list, :atom},
              default: [],
              doc:
                "Leaves these modules out of the compared call stacks, such as wrappers around Repo."
            ],
            min_duration_ms: [
              type: :non_neg_integer,
              default: 0,
              doc: "Reports only N+1 queries that took at least this long in total."
            ],
            sample_rate: [
              type: {:custom, __MODULE__, :sample_rate, []},
              default: 1.0,
              doc:
                "Sets the share of requests and jobs to scan, from 0 to 1. Tests are always scanned."
            ],
            log: [
              type: :boolean,
              default: true,
              doc: "Prints each N+1 to standard error."
            ],
            github_annotations: [
              type: :boolean,
              doc: "Prints GitHub Actions annotations. On by default inside GitHub Actions."
            ],
            json_report: [
              type: {:or, [:string, nil]},
              default: nil,
              doc: "Appends each N+1 to this file as a line of JSON."
            ]
          )

  @moduledoc """
  Catches N+1 queries while your tests run and while you use the app in dev.

  It reports a query that ran at least `:threshold` times, two by default, from the same call stack in one unit of work.
  Each test, request, LiveView event and Oban job is a unit.
  Only reads count, never inserts, updates or deletes.

  Turn on stack traces for the repo in `config/dev.exs` and `config/test.exs` so findings point at your code.

      config :my_app, MyApp.Repo, stacktrace: true

  Attach it in `test/test_helper.exs` and scan every test from your case templates.

      EctoDoctor.RepeatedQueries.attach(repo: MyApp.Repo)

      # in the setup of DataCase and ConnCase
      setup tags do
        :ok = EctoDoctor.RepeatedQueries.scan_test(tags)
        MyApp.DataCase.setup_sandbox(tags)
        :ok
      end

  A test tagged `@tag repeated_queries: false` isn't scanned.
  `mix ecto_doctor.install` does all of this for you.

  ## Adopting it in an existing app

  Until the baseline file exists findings only print.
  Run `ECTO_DOCTOR_RECORD=1 mix test` once to record the N+1 queries you have today.
  From then on only new ones fail a test.

  ## Options

  #{NimbleOptions.docs(@schema)}

  ## Telemetry

  Each finding emits `[:ecto_doctor, :repeated_query]` with `:count` and `:duration_ms`.
  Its metadata holds `:sql`, `:frames`, `:fix`, `:key` and `:label`.
  """

  require Logger

  alias EctoDoctor.Baseline
  alias EctoDoctor.RepeatedQueries.Finding
  alias EctoDoctor.RepeatedQueries.Query
  alias EctoDoctor.RepeatedQueries.Report
  alias EctoDoctor.RepeatedQueries.Store
  alias EctoDoctor.RepeatedQueries.Watcher
  alias EctoDoctor.Schema

  @units [
    [:phoenix, :endpoint],
    [:phoenix, :live_view, :mount],
    [:phoenix, :live_view, :handle_params],
    [:phoenix, :live_view, :handle_event],
    [:oban, :job]
  ]

  @doc """
  Starts watching the repo's queries.

  Call it once in `test/test_helper.exs` or when your app starts in dev.
  """
  @spec attach(keyword()) :: :ok
  def attach(opts) do
    opts =
      opts
      |> Keyword.put_new(:github_annotations, System.get_env("GITHUB_ACTIONS") == "true")
      |> NimbleOptions.validate!(@schema)

    detach()

    repos = List.wrap(Keyword.fetch!(opts, :repo))
    apps = Keyword.get_lazy(opts, :apps, fn -> Enum.map(repos, & &1.config()[:otp_app]) end)

    baseline = Keyword.fetch!(opts, :baseline)

    config =
      opts
      |> Map.new()
      |> Map.put(:repos, repos)
      |> Map.put(:apps, MapSet.new(apps))
      |> Map.put(:schemas, apps |> Enum.flat_map(&Schema.modules/1) |> Schema.all())
      |> Map.put(:known, MapSet.new(Baseline.read!(baseline).repeated_queries))
      # Until a baseline exists findings only print so day one never breaks a suite
      |> Map.put(:strict?, strict?(Keyword.fetch!(opts, :mode), baseline))

    {:ok, _pid} = Watcher.start()

    :persistent_term.put(__MODULE__, config)

    query_events = Enum.map(repos, &query_event/1)
    :telemetry.attach_many({__MODULE__, :queries}, query_events, &__MODULE__.handle_query/4, nil)
    :telemetry.attach_many({__MODULE__, :units}, unit_events(), &__MODULE__.handle_unit/4, nil)

    if Report.recording?() do
      ExUnit.after_suite(fn _result -> Report.write_recorded(baseline) end)
    end

    :ok
  end

  @doc "Stops watching."
  @spec detach() :: :ok
  def detach do
    :telemetry.detach({__MODULE__, :queries})
    :telemetry.detach({__MODULE__, :units})

    Watcher.stop()
    :persistent_term.erase(__MODULE__)
    :ok
  end

  @doc false
  @spec attached?() :: boolean()
  def attached?, do: :persistent_term.get(__MODULE__, nil) != nil and Store.ready?()

  @doc """
  Scans one ExUnit test and fails it on a new N+1 query.

      setup {EctoDoctor.RepeatedQueries, :scan_test}
  """
  @spec scan_test(map()) :: :ok
  def scan_test(%{repeated_queries: false}), do: :ok

  def scan_test(context) do
    ensure_attached!()
    owner = Store.start("#{inspect(context.module)} #{context.test}")

    ExUnit.Callbacks.on_exit(fn ->
      owner
      |> Store.close()
      |> scan_findings()
      |> Report.report!(config())
    end)

    :ok
  end

  @doc """
  Scans the code in the function and reports its N+1 queries without raising.

  The label shows in each finding. It returns what the function returns.

      EctoDoctor.RepeatedQueries.scan("nightly import", &Importer.run_nightly/0)
  """
  @spec scan(nil | String.t(), (-> result)) :: result when result: term()
  def scan(label \\ nil, fun) do
    ensure_attached!()
    owner = Store.start(label)

    try do
      fun.()
    after
      finish(owner)
    end
  end

  @doc """
  Leaves the code in the function out of the scan it runs in and returns what the function returns.
  """
  @spec pause((-> result)) :: result when result: term()
  def pause(fun) do
    owner = Store.owner()
    if owner != nil, do: Store.pause(owner)

    try do
      fun.()
    after
      if owner != nil and Store.open?(owner), do: Store.resume(owner)
    end
  end

  @doc """
  Runs the function in a scan of its own and returns its N+1 queries without reporting them.

  The assertions in `EctoDoctor.RepeatedQueries.Assertions` use it.
  """
  @spec findings((-> term())) :: [Finding.t()]
  def findings(fun) do
    mark = System.unique_integer([:monotonic])
    owner = Store.start(nil)

    try do
      fun.()

      owner
      |> Store.take_after(mark)
      |> Store.findings(config(), nil)
    after
      Store.finish(owner)
    end
  end

  @doc false
  @spec start_page(String.t()) :: pid()
  def start_page(label), do: Store.start_watched(label)

  @doc false
  @spec peek(pid()) :: [Finding.t()]
  def peek(owner), do: Store.findings(Store.queries(owner), config(), nil)

  @doc false
  @spec finish(pid()) :: [Finding.t()]
  def finish(owner) do
    owner
    |> Store.finish()
    |> scan_findings()
    |> Report.report(config())
  end

  # A nested scan ends without findings since the outer scan reports them
  defp scan_findings(nil), do: []
  defp scan_findings({label, queries}), do: Store.findings(queries, config(), label)

  # Telemetry detaches a handler that raises so both handlers rescue to keep detection running
  @doc false
  def handle_query(_event, measurements, metadata, _config) do
    record(measurements, metadata)
  rescue
    error ->
      warn_once(:failed, "Ecto Doctor stopped recording N+1 queries. #{Exception.message(error)}")
  end

  defp record(measurements, metadata) do
    owner = Store.owner()

    if watched?(owner, metadata.query) do
      config = config()
      frames = Query.frames(metadata[:stacktrace], config.apps, config.ignore_frames)
      add(owner, frames, measurements, metadata)
    end
  end

  # A query whose stack has no app code has nothing to point at, such as one from a library process
  defp add(_owner, [], _measurements, %{stacktrace: [_ | _]}), do: :ok

  defp add(owner, frames, measurements, metadata) do
    native = measurements.total_time

    query = %{
      sql: metadata.query,
      frames: frames,
      microseconds: System.convert_time_unit(native, :native, :microsecond),
      source: metadata[:source],
      unit: Store.unit()
    }

    if Store.add(owner, query) == :full do
      warn_once(
        :full,
        "Ecto Doctor stopped recording a scan after #{Store.max_queries()} queries."
      )
    end
  end

  defp watched?(nil, _sql), do: false
  defp watched?(owner, sql), do: Query.select?(sql) and Store.counting?(owner)

  @doc false
  def handle_unit(event, _measurements, metadata, _config) do
    unit(List.last(event), event, metadata)
  rescue
    error ->
      warn_once(:failed, "Ecto Doctor stopped recording N+1 queries. #{Exception.message(error)}")
  end

  defp unit(:start, event, metadata), do: start_unit(event, metadata)
  defp unit(suffix, _event, _metadata) when suffix in [:stop, :exception], do: stop_unit()

  # Recording that stops would make every test pass quietly so it says so once
  defp warn_once(kind, message) do
    if Store.first_warning?(kind), do: Logger.warning(message)
    :ok
  end

  # A request that raised never sent its stop event so a new request in the same process clears it
  defp start_unit([:phoenix, :endpoint, :start] = event, metadata) do
    Store.reset(self())
    open_unit(event, metadata)
  end

  defp start_unit(event, metadata), do: open_unit(event, metadata)

  # A unit nested in a scan always joins it while a new one is sampled so a skipped unit records nothing
  defp open_unit(event, metadata) do
    if Store.owner() != nil or :rand.uniform() < config().sample_rate do
      Store.start_watched(label(event, metadata))
      Store.enter_unit()
    end
  end

  defp stop_unit do
    Store.leave_unit()

    case Store.owner() do
      nil -> :ok
      owner -> finish(owner)
    end
  end

  defp strict?(:raise, baseline) when is_binary(baseline), do: File.exists?(baseline)
  defp strict?(_mode, _baseline), do: false

  @doc false
  @spec sample_rate(term()) :: {:ok, number()} | {:error, String.t()}
  def sample_rate(rate) when is_number(rate) and rate >= 0 and rate <= 1, do: {:ok, rate}

  def sample_rate(rate),
    do: {:error, "expected :sample_rate to be a number from 0 to 1, got #{inspect(rate)}"}

  defp ensure_attached! do
    if not attached?() do
      raise ArgumentError,
            "Call EctoDoctor.RepeatedQueries.attach/1 first, such as in test/test_helper.exs."
    end
  end

  defp config, do: :persistent_term.get(__MODULE__)

  defp query_event(repo) do
    default = repo |> Module.split() |> Enum.map(&String.to_atom(Macro.underscore(&1)))
    Keyword.get(repo.config(), :telemetry_prefix, default) ++ [:query]
  end

  defp unit_events do
    for unit <- @units, suffix <- [:start, :stop, :exception], do: unit ++ [suffix]
  end

  defp label([:phoenix, :endpoint, _], %{conn: conn}), do: "#{conn.method} #{conn.request_path}"

  defp label([:phoenix, :live_view, callback, _], %{socket: socket}) do
    "#{inspect(socket.view)} #{callback}"
  end

  defp label([:oban, :job, _], %{job: job}), do: job.worker
  defp label(_event, _metadata), do: nil
end
