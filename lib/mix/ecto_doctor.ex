defmodule Mix.EctoDoctor do
  @moduledoc false

  @doc "Starts the repo if needed, runs every check and raises when Ecto Doctor can't run."
  @spec diagnose!(Ecto.Repo.t(), keyword()) :: [EctoDoctor.Finding.t()]
  def diagnose!(repo, opts) do
    case Ecto.Migrator.with_repo(repo, &EctoDoctor.diagnose(&1, opts)) do
      {:ok, {:ok, findings}, _apps} ->
        findings

      {:ok, {:error, error}, _apps} ->
        Mix.raise(error.message)

      {:error, reason} ->
        Mix.raise("Ecto Doctor couldn't start #{inspect(repo)}. #{inspect(reason)}")
    end
  end
end
