defmodule EctoDoctor.Report.Printable do
  @moduledoc false

  # Names from the database and SQL from the app could hold characters that steer a terminal
  # Characters that flip how a line reads print as ? too
  @control_characters Enum.map(Enum.to_list(0..31) -- [?\n], &<<&1>>) ++
                        Enum.map(Enum.to_list(127..159), &<<&1::utf8>>) ++
                        Enum.map(
                          Enum.to_list(0x202A..0x202E) ++ Enum.to_list(0x2066..0x2069),
                          &<<&1::utf8>>
                        )

  @doc "Replaces characters that could steer a terminal with ?."
  @spec clean(String.t()) :: String.t()
  def clean(text), do: String.replace(text, @control_characters, "?")

  @doc "Indents every line after the first so none of them can start a GitHub workflow command."
  @spec indent(String.t()) :: String.t()
  def indent(text), do: String.replace(text, "\n", "\n    ")
end
