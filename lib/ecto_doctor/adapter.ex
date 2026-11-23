defmodule EctoDoctor.Adapter do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias EctoDoctor.Adapter.MySQL
  alias EctoDoctor.Adapter.Postgres
  alias EctoDoctor.Adapter.SQLite
  alias EctoDoctor.Database

  @callback read(repo :: Ecto.Repo.t(), prefixes :: [nil | String.t()]) :: Database.t()
  @callback check_version(repo :: Ecto.Repo.t()) :: :ok | {:error, String.t()}

  @spec for_repo(Ecto.Repo.t()) :: {:ok, module()} | {:error, String.t()}
  def for_repo(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> {:ok, Postgres}
      Ecto.Adapters.MyXQL -> {:ok, MySQL}
      Ecto.Adapters.SQLite3 -> {:ok, SQLite}
      adapter -> {:error, "Ecto Doctor doesn't support #{inspect(adapter)}."}
    end
  end

  @spec rows(Ecto.Repo.t(), String.t(), list()) :: [map()]
  def rows(repo, sql, params) do
    %{columns: columns, rows: rows} = SQL.query!(repo, sql, params, log: false)
    Enum.map(rows, fn row -> columns |> Enum.zip(row) |> Map.new() end)
  end

  @spec table_key(map()) :: {nil | String.t(), String.t()}
  def table_key(row), do: {row["prefix"], row["table_name"]}

  @spec at_least?(String.t(), {non_neg_integer(), non_neg_integer()}) :: boolean()
  def at_least?(version, minimum) do
    [major, minor | _rest] = String.split(version, [".", "-"])
    {major, _rest} = Integer.parse(major)
    {minor, _rest} = Integer.parse(minor)

    {major, minor} >= minimum
  end

  @doc "Reads the values of a list like ('a', 'b') where every second piece between quotes is a value."
  @spec quoted_values(String.t()) :: [String.t()]
  def quoted_values(text) do
    text
    |> String.split("'")
    |> Enum.drop(1)
    |> Enum.take_every(2)
  end
end
