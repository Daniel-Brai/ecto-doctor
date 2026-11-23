defmodule Mix.Tasks.EctoDoctor.Install do
  @shortdoc "Sets Ecto Doctor up in your app"

  @moduledoc """
  Sets Ecto Doctor up in your app.

      mix ecto_doctor.install

  It only adds lines and prints what it couldn't do.

    * It turns on `stacktrace: true` for each repo in `config/dev.exs` and `config/test.exs`.
    * It attaches N+1 detection in `test/test_helper.exs`.
    * It scans every test from `test/support/data_case.ex` and `test/support/conn_case.ex`.
  """

  use Mix.Task

  @recursive true

  @setup "  setup tags do\n"
  @scan "    :ok = EctoDoctor.RepeatedQueries.scan_test(tags)\n"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    repos = Mix.Ecto.parse_repo(args)
    config_dir = Path.dirname(Mix.Project.config()[:config_path])

    # The repo's own app owns its config, which in an umbrella isn't always the app running this
    for repo <- repos, file <- ~w[dev.exs test.exs] do
      line = "config #{inspect(repo.config()[:otp_app])}, #{inspect(repo)}, stacktrace: true"
      append(Path.join(config_dir, file), line, line)
    end

    if repos != [] do
      append("test/test_helper.exs", attach_line(repos), "EctoDoctor")
    end

    scan_tests("test/support/data_case.ex")
    scan_tests("test/support/conn_case.ex")

    Mix.shell().info("""

    Run this once to record the N+1 queries your tests have today.
    After that only new ones fail a test.

        ECTO_DOCTOR_RECORD=1 mix test

    Then run mix ecto.doctor to check your schemas against the database.
    """)
  end

  defp attach_line([repo]), do: "EctoDoctor.RepeatedQueries.attach(repo: #{inspect(repo)})"

  defp attach_line(repos) do
    names = Enum.map_join(repos, ", ", &inspect/1)
    "EctoDoctor.RepeatedQueries.attach(repo: [#{names}])"
  end

  defp append(path, line, marker) do
    case File.read(path) do
      {:ok, code} ->
        append_line(path, code, line, marker)

      {:error, _reason} ->
        Mix.shell().info(
          "Skipped #{path} because it doesn't exist. Add this line yourself.\n    #{line}"
        )
    end
  end

  defp append_line(path, code, line, marker) do
    if String.contains?(code, marker) do
      :ok
    else
      File.write!(path, String.trim_trailing(code) <> "\n\n" <> line <> "\n")
      Mix.shell().info("Added to #{path}")
    end
  end

  defp scan_tests(path) do
    case File.read(path) do
      {:ok, code} -> add_scan(path, code)
      {:error, _reason} -> :ok
    end
  end

  defp add_scan(path, code) do
    cond do
      String.contains?(code, "EctoDoctor") ->
        :ok

      String.contains?(code, @setup) ->
        File.write!(path, String.replace(code, @setup, @setup <> @scan, global: false))
        Mix.shell().info("Added to #{path}")

      true ->
        Mix.shell().info("Add this line to the start of the setup in #{path}.\n" <> @scan)
    end
  end
end
