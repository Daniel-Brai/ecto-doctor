defmodule EctoDoctor.RepeatedQueries.Report do
  @moduledoc false

  alias EctoDoctor.Baseline
  alias EctoDoctor.RepeatedQueries.Error
  alias EctoDoctor.RepeatedQueries.Finding
  alias EctoDoctor.RepeatedQueries.Store
  alias EctoDoctor.Report.GitHub
  alias EctoDoctor.Report.Printable

  @doc """
  Prints the findings the baseline doesn't know and returns them.

  While ECTO_DOCTOR_RECORD is set they go into the baseline instead.
  """
  @spec report([Finding.t()], map()) :: [Finding.t()]
  def report(findings, config) do
    new = Enum.reject(findings, &MapSet.member?(config.known, &1.key))

    if recording?() do
      Store.record(Enum.map(new, & &1.key))
      []
    else
      Enum.each(new, &emit(&1, config))
      new
    end
  end

  @doc "Reports like `report/2` and raises in `:raise` mode once the app has a baseline file."
  @spec report!([Finding.t()], map()) :: [Finding.t()]
  def report!(findings, config) do
    new = report(findings, config)

    if new != [] and config.strict? do
      raise Error, message: Enum.map_join(new, "\n\n", &format/1)
    end

    new
  end

  @spec recording?() :: boolean()
  def recording?, do: System.get_env("ECTO_DOCTOR_RECORD") in ["1", "true"]

  @spec write_recorded(nil | Path.t()) :: :ok
  def write_recorded(nil), do: :ok

  def write_recorded(baseline) do
    known = Baseline.read!(baseline).repeated_queries
    Baseline.write(baseline, :repeated_queries, known ++ Store.recorded())
  end

  @spec format(Finding.t()) :: String.t()
  def format(%Finding{} = finding) do
    where = if finding.label, do: " in #{finding.label}", else: ""
    duration = Float.round(finding.duration_ms, 1)

    head =
      "N+1 query#{where}. It ran #{finding.count} times in #{duration} ms#{origin(finding.origin)}."

    frames =
      Enum.map(finding.frames, fn {module, fun, arity, file, line} ->
        "  #{file}:#{line} #{inspect(module)}.#{fun}/#{arity}"
      end)

    fix = if finding.fix, do: ["  " <> finding.fix], else: []

    ([head, "  " <> Printable.indent(finding.sql)] ++ frames ++ fix)
    |> Enum.join("\n")
    |> Printable.clean()
  end

  defp origin(nil), do: ""

  defp origin({module, fun, arity, file, line}) do
    " from #{inspect(module)}.#{fun}/#{arity} at #{file}:#{line}"
  end

  defp emit(finding, config) do
    measurements = %{count: finding.count, duration_ms: finding.duration_ms}

    metadata = %{
      sql: finding.sql,
      frames: finding.frames,
      fix: finding.fix,
      key: finding.key,
      label: finding.label
    }

    :telemetry.execute([:ecto_doctor, :repeated_query], measurements, metadata)

    if config.log, do: IO.puts(:stderr, format(finding))
    if config.github_annotations, do: IO.puts(annotation(finding))
    if config.json_report, do: File.write!(config.json_report, json(finding) <> "\n", [:append])
  end

  defp annotation(%Finding{} = finding) do
    message = GitHub.data("It ran #{finding.count} times. #{finding.sql}")
    "::warning #{annotation_place(finding.origin)}title=N+1 query::#{message}"
  end

  defp annotation_place(nil), do: ""

  defp annotation_place({_module, _fun, _arity, file, line}) do
    "file=#{GitHub.property(file)},line=#{line},"
  end

  defp json(%Finding{} = finding) do
    finding
    |> Map.from_struct()
    |> Map.put(:frames, Enum.map(finding.frames, &frame_map/1))
    |> Map.put(:origin, frame_map(finding.origin))
    |> JSON.encode!()
  end

  defp frame_map(nil), do: nil

  defp frame_map({module, fun, arity, file, line}) do
    %{call: "#{inspect(module)}.#{fun}/#{arity}", file: file, line: line}
  end
end
