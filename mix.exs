defmodule EctoDoctor.MixProject do
  use Mix.Project

  @version "0.0.1"
  @source_url "https://github.com/Daniel-Brai/ecto-doctor"

  def project do
    [
      app: :ecto_doctor,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Catch Ecto schema mismatches and N+1 queries in development",
      package: package(),
      name: "Ecto Doctor",
      source_url: @source_url,
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      test_coverage: [tool: ExCoveralls],
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [check: :test, coveralls: :test, "coveralls.html": :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.0"},
      {:postgrex, "~> 0.19", optional: true},
      {:plug, "~> 1.14", optional: true},
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:ex_doc, "0.40.4", only: :dev, runtime: false},
      {:dialyxir, "1.4.9", only: [:dev, :test], runtime: false},
      {:excoveralls, "0.18.5", only: :test},
      {:faker, "0.19.0", only: :test},
      {:myxql, "0.9.0", only: :test},
      {:ecto_sqlite3, "0.26.0", only: :test}
    ]
  end

  defp aliases do
    [
      test: [
        "ecto.drop --quiet",
        "ecto.create --quiet",
        "ecto.migrate --quiet --migrations-path test/support/migrations",
        "test"
      ],
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors --force",
        "credo --strict",
        "coveralls"
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Daniel Brai"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w[lib mix.exs README.md CHANGELOG.md LICENSE]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Schema checks": [
          EctoDoctor,
          EctoDoctor.Finding,
          EctoDoctor.Error
        ],
        "N+1 queries": [
          EctoDoctor.RepeatedQueries,
          EctoDoctor.RepeatedQueries.Assertions,
          EctoDoctor.RepeatedQueries.Finding,
          EctoDoctor.RepeatedQueries.Error,
          EctoDoctor.Plug
        ]
      ]
    ]
  end
end
