defmodule EctoDoctor.Report.GitHub do
  @moduledoc false

  alias EctoDoctor.Finding

  @levels %{error: "error", warning: "warning", info: "notice"}

  @spec format([Finding.t()]) :: String.t()
  def format(findings) do
    Enum.map_join(findings, fn finding -> line(finding) <> "\n" end)
  end

  defp line(%Finding{} = finding) do
    level = Map.fetch!(@levels, finding.level)
    title = property(finding.check)
    "::#{level} #{place(finding)}title=#{title}::#{data(finding.message)}"
  end

  @doc "Escapes the message of a workflow command so it can't start a new command."
  @spec data(String.t()) :: String.t()
  def data(text) do
    text
    |> String.replace("%", "%25")
    |> String.replace("\r", "%0D")
    |> String.replace("\n", "%0A")
  end

  defp place(%Finding{file: nil}), do: ""
  defp place(%Finding{line: nil} = finding), do: "file=#{property(finding.file)},"

  defp place(%Finding{} = finding) do
    "file=#{property(finding.file)},line=#{finding.line},"
  end

  @doc "Escapes a workflow command property such as a file path."
  @spec property(term()) :: String.t()
  def property(value) do
    value
    |> to_string()
    |> data()
    |> String.replace(":", "%3A")
    |> String.replace(",", "%2C")
  end
end
