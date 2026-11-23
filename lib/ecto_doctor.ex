defmodule EctoDoctor do
  @moduledoc """
  Finds where your Ecto schemas and changesets disagree with your database.

  Most people run it with `mix ecto.doctor`.
  Call `diagnose/2` to use the findings in your own code.

      {:ok, findings} = EctoDoctor.diagnose(MyApp.Repo)

  It reads your schemas through reflection and your changesets from source.
  Then it reads the live database and compares the three.
  Nothing is written.

  ## Options

  #{EctoDoctor.Config.docs()}

  ## Config file

  `mix ecto.doctor` also reads `.ecto_doctor.exs` from the project root.
  It holds the same options as a keyword list.

      [
        checks: [orphan_table: [ignore: ["legacy_*"]], string_length_overflow: false],
        ignore_tables: ["schema_migrations", "oban_*", "pg_search_documents"]
      ]

  A schema can also turn checks off for itself with a comment like `# ecto_doctor:ignore missing_not_null` inside its module.
  """

  alias EctoDoctor.Baseline
  alias EctoDoctor.Checks
  alias EctoDoctor.Config
  alias EctoDoctor.Error
  alias EctoDoctor.Finding
  alias EctoDoctor.Model

  @doc """
  Runs every check against the repo and returns the findings with the most severe first.

  Findings listed in the baseline file are left out.
  """
  @spec diagnose(Ecto.Repo.t(), keyword()) :: {:ok, [Finding.t()]} | {:error, Error.t()}
  def diagnose(repo, opts \\ []) do
    with {:ok, opts} <- Config.validate(opts),
         {:ok, baseline} <- Baseline.load(Keyword.fetch!(opts, :baseline)),
         {:ok, model} <- Model.build(repo, opts) do
      findings = Checks.run(model, opts)

      known = MapSet.new(baseline.findings)
      {:ok, Enum.reject(findings, &MapSet.member?(known, Finding.key(&1)))}
    end
  end
end
