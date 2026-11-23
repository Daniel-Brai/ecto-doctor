defmodule Mix.Tasks.Ecto.Doctor do
  @shortdoc "Checks your schemas and changesets against the database"

  @moduledoc """
  Checks your Ecto schemas and changesets against the live database.

      mix ecto.doctor

  It exits with status 1 when a finding is at or above `--fail-on` so it can run in CI as it is.

  ## Flags

    * `--repo` or `-r` picks the repo. Repeat it for several. Defaults to the app's `ecto_repos`.
    * `--only` runs only these checks, as a comma separated list.
    * `--except` skips these checks.
    * `--all` reports info level findings too.
    * `--format` is `text`, `json`, `sarif` or `github`. Defaults to `text`.
    * `--fail-on` is `error`, `warning` or `info`. Defaults to `error`.
    * `--fix` writes migrations for every fix a migration can make. On PostgreSQL indexes are built concurrently and constraints are validated in a later migration.
    * `--apply` runs only those migrations after you confirm.
    * `--no-baseline` reports findings the baseline file would leave out.
    * `--config` reads options from this file. Defaults to `.ecto_doctor.exs`.

  `mix ecto.doctor.explain` describes every check.
  """

  use Mix.Task

  alias EctoDoctor.Config
  alias EctoDoctor.Finding
  alias EctoDoctor.Fix
  alias EctoDoctor.Report.GitHub
  alias EctoDoctor.Report.JSON
  alias EctoDoctor.Report.SARIF
  alias EctoDoctor.Report.Text

  @recursive true

  @switches [
    repo: :keep,
    only: :string,
    except: :string,
    all: :boolean,
    format: :string,
    fail_on: :string,
    fix: :boolean,
    apply: :boolean,
    baseline: :boolean,
    config: :string
  ]

  @formats %{"text" => Text, "json" => JSON, "sarif" => SARIF, "github" => GitHub}

  @impl Mix.Task
  def run(args) do
    {flags, _rest} = OptionParser.parse!(args, strict: @switches, aliases: [r: :repo])
    Mix.Task.run("app.config")

    opts = options(flags)
    format = Keyword.get(flags, :format, "text")
    report = report(format)
    fail_on = fail_on(Keyword.get(flags, :fail_on, "error"))

    # Lines about written migrations would break JSON or SARIF that another tool reads
    if flags[:fix] == true and format != "text",
      do: Mix.raise("--fix works with the text format only.")

    findings = args |> Mix.Ecto.parse_repo() |> Enum.flat_map(&diagnose(&1, opts, flags))
    Mix.shell().info(report.format(findings))

    failed? =
      Enum.any?(findings, fn finding -> Finding.rank(finding.level) <= Finding.rank(fail_on) end)

    if failed?, do: exit({:shutdown, 1})
  end

  defp options(flags) do
    file_opts = Config.read_file(Keyword.get(flags, :config, Config.default_path()))

    cli_opts =
      [all: flags[:all], only: check_ids(flags[:only]), except: check_ids(flags[:except])]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    opts = Keyword.merge(file_opts, cli_opts)

    if flags[:baseline] == false do
      Keyword.put(opts, :baseline, nil)
    else
      opts
    end
  end

  defp check_ids(nil), do: nil

  defp check_ids(text) do
    ids = Map.new(EctoDoctor.Checks.all(), &{to_string(&1.id()), &1.id()})

    text
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&check_id(&1, ids))
  end

  # A misspelled check would otherwise run nothing and pass
  defp check_id(name, ids) do
    case Map.fetch(ids, name) do
      {:ok, id} -> id
      :error -> Mix.raise("Unknown check #{name}. Run mix ecto.doctor.explain to list them.")
    end
  end

  defp report(format) do
    case Map.fetch(@formats, format) do
      {:ok, report} -> report
      :error -> Mix.raise("Unknown --format #{format}. Use text, json, sarif or github.")
    end
  end

  defp fail_on(level) when level in ~w[error warning info], do: String.to_atom(level)
  defp fail_on(level), do: Mix.raise("Unknown --fail-on #{level}. Use error, warning or info.")

  defp diagnose(repo, opts, flags) do
    findings = Mix.EctoDoctor.diagnose!(repo, opts)
    if flags[:fix], do: fix(repo, findings, flags[:apply])
    findings
  end

  defp fix(repo, findings, apply?) do
    # The project's own priv folder, since the one Ecto.Migrator knows is the compiled copy in _build
    dir = Path.join(Mix.EctoSQL.source_repo_priv(repo), "migrations")

    case Fix.write_migrations(repo, findings, dir) do
      [] ->
        Mix.shell().info("No finding has a migration to write.")

      paths ->
        Enum.each(paths, &Mix.shell().info("Wrote #{Path.relative_to_cwd(&1)}"))
        apply_migrations(repo, paths, apply?)
    end
  end

  defp apply_migrations(repo, paths, true) do
    if Mix.shell().yes?("Run these migrations now?") do
      Ecto.Migrator.with_repo(repo, &Fix.apply_migrations(&1, paths))
    end
  end

  defp apply_migrations(_repo, _paths, _apply?) do
    Mix.shell().info("Read them before you run them.")
  end
end
