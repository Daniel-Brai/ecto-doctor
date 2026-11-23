defmodule EctoDoctor.Report.Text do
  @moduledoc false

  alias EctoDoctor.Finding
  alias EctoDoctor.Report.Printable

  @spec format([Finding.t()]) :: String.t()
  def format([]), do: "No problems found.\n"

  def format(findings) do
    Enum.map_join(findings, "\n", &finding/1) <> "\n" <> summary(findings) <> "\n"
  end

  defp finding(%Finding{} = finding) do
    location = [finding.file, finding.line] |> Enum.reject(&is_nil/1) |> Enum.join(":")
    head = Enum.join([String.pad_trailing("#{finding.level}", 8), finding.check, location], "  ")

    [
      head,
      "  " <> Printable.indent(finding.message),
      extra("fix", finding.fix),
      migration(finding.migration)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Printable.clean()
  end

  defp migration([]), do: nil
  defp migration(steps), do: extra("migration", Enum.map_join(steps, "\n", &elem(&1, 1)))

  defp extra(_label, nil), do: nil
  defp extra(label, text), do: "  #{label}: " <> Printable.indent(text)

  defp summary(findings) do
    findings
    |> Enum.frequencies_by(& &1.level)
    |> Enum.sort_by(fn {level, _count} -> Finding.rank(level) end)
    |> Enum.map(fn {level, count} -> count(count, level) end)
    |> sentence()
  end

  defp count(1, level), do: "1 #{level}"
  defp count(count, :info), do: "#{count} info"
  defp count(count, level), do: "#{count} #{level}s"

  defp sentence([only]), do: only
  defp sentence(parts), do: Enum.join(Enum.drop(parts, -1), ", ") <> " and " <> List.last(parts)
end
