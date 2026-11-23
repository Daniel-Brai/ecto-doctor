defmodule Mix.Tasks.Ecto.Doctor.Baseline do
  @shortdoc "Records today's findings so later runs report only new ones"

  @moduledoc """
  Writes every current finding to the baseline file so `mix ecto.doctor` reports only new ones.

      mix ecto.doctor.baseline

  It takes `--repo` and `--config` like `mix ecto.doctor`.
  Delete a line from the file once you fix that finding so it's caught if it comes back.
  """

  use Mix.Task

  alias EctoDoctor.Baseline
  alias EctoDoctor.Config
  alias EctoDoctor.Finding

  @recursive true

  @switches [repo: :keep, config: :string]

  @impl Mix.Task
  def run(args) do
    {flags, _rest} = OptionParser.parse!(args, strict: @switches, aliases: [r: :repo])

    Mix.Task.run("app.config")

    file_opts = Config.read_file(Keyword.get(flags, :config, Config.default_path()))
    path = baseline_path(file_opts)
    opts = Keyword.merge(file_opts, all: true, baseline: nil)

    keys =
      args
      |> Mix.Ecto.parse_repo()
      |> Enum.flat_map(&Mix.EctoDoctor.diagnose!(&1, opts))
      |> Enum.map(&Finding.key/1)
      |> Enum.uniq()

    Baseline.write(path, :findings, keys)
    Mix.shell().info("Wrote #{count(keys)} to #{path}.")
  end

  defp count([_one]), do: "1 finding"
  defp count(keys), do: "#{length(keys)} findings"

  defp baseline_path(file_opts) do
    case Keyword.get(file_opts, :baseline, Baseline.default_path()) do
      nil -> Mix.raise("The config sets baseline: nil so there is no file to write.")
      path -> path
    end
  end
end
