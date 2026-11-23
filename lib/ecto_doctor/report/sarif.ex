defmodule EctoDoctor.Report.SARIF do
  @moduledoc false

  alias EctoDoctor.Check
  alias EctoDoctor.Checks
  alias EctoDoctor.Finding

  @levels %{error: "error", warning: "warning", info: "note"}

  @spec format([Finding.t()]) :: String.t()
  def format(findings) do
    JSON.encode!(%{
      "$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
      "version" => "2.1.0",
      "runs" => [
        %{
          "tool" => tool(),
          "results" => findings |> Enum.filter(&(&1.file != nil)) |> Enum.map(&result/1)
        }
      ]
    })
  end

  defp tool do
    rules =
      Enum.map(Checks.all(), fn check ->
        %{"id" => to_string(check.id()), "shortDescription" => %{"text" => Check.summary(check)}}
      end)

    %{
      "driver" => %{
        "name" => "Ecto Doctor",
        "informationUri" => "https://hex.pm/packages/ecto_doctor",
        "rules" => rules
      }
    }
  end

  defp result(%Finding{} = finding) do
    %{
      "ruleId" => to_string(finding.check),
      "level" => Map.fetch!(@levels, finding.level),
      "message" => %{"text" => finding.message},
      "locations" => locations(finding)
    }
  end

  defp locations(%Finding{} = finding) do
    [%{"physicalLocation" => physical_location(finding)}]
  end

  defp physical_location(%Finding{line: nil} = finding) do
    %{"artifactLocation" => %{"uri" => finding.file}}
  end

  defp physical_location(%Finding{} = finding) do
    %{"artifactLocation" => %{"uri" => finding.file}, "region" => %{"startLine" => finding.line}}
  end
end
