defmodule EctoDoctor.Baseline do
  @moduledoc false

  alias EctoDoctor.Error

  @type t :: %{findings: [String.t()], repeated_queries: [String.t()]}

  @default_path ".ecto_doctor_baseline.exs"

  @spec default_path() :: Path.t()
  def default_path, do: @default_path

  @doc "Reads the baseline file or explains why it can't and treats a missing file as empty."
  @spec load(nil | Path.t()) :: {:ok, t()} | {:error, Error.t()}
  def load(nil), do: {:ok, empty()}

  def load(path) do
    case File.read(path) do
      {:ok, text} ->
        parse(path, text)

      {:error, :enoent} ->
        {:ok, empty()}

      {:error, reason} ->
        {:error, %Error{message: "Can't read #{path}. #{:file.format_error(reason)}"}}
    end
  end

  @doc "Reads the baseline file and raises when it can't so writing it never wipes what it held."
  @spec read!(nil | Path.t()) :: t()
  def read!(path) do
    case load(path) do
      {:ok, baseline} -> baseline
      {:error, error} -> raise error
    end
  end

  defp parse(path, text) do
    case Code.string_to_quoted(text, existing_atoms_only: true) do
      {:ok, {:%{}, _meta, pairs}} -> {:ok, Enum.reduce(pairs, empty(), &put_keys/2)}
      _other -> {:error, %Error{message: "#{path} isn't a baseline map. Fix it or delete it."}}
    end
  end

  @spec write(Path.t(), atom(), [String.t()]) :: :ok
  def write(path, section, keys) do
    keys = keys |> Enum.uniq() |> Enum.sort()
    baseline = path |> read!() |> Map.put(section, keys)

    File.write!(
      path,
      inspect(baseline, pretty: true, limit: :infinity, printable_limit: :infinity) <> "\n"
    )
  end

  # The file is parsed and never run so only lists of strings are read from it
  defp put_keys({key, keys}, baseline)
       when key in [:findings, :repeated_queries] and is_list(keys) do
    Map.put(baseline, key, Enum.filter(keys, &is_binary/1))
  end

  defp put_keys(_pair, baseline), do: baseline

  defp empty, do: %{findings: [], repeated_queries: []}
end
