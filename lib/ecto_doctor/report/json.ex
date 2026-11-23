defmodule EctoDoctor.Report.JSON do
  @moduledoc false

  alias EctoDoctor.Finding

  @spec format([Finding.t()]) :: String.t()
  def format(findings), do: findings |> Enum.map(&to_map/1) |> JSON.encode!()

  defp to_map(%Finding{} = finding) do
    steps = Enum.map(finding.migration, fn {phase, line} -> %{phase: phase, line: line} end)

    %{Map.from_struct(finding) | schema: schema_name(finding.schema), migration: steps}
  end

  defp schema_name(nil), do: nil
  defp schema_name(module), do: inspect(module)
end
