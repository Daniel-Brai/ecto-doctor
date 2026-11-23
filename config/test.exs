import Config

config :ecto_doctor, ecto_repos: [EctoDoctor.Test.Repo]

config :ecto_doctor, EctoDoctor.Test.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ecto_doctor_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  stacktrace: true

config :ecto_doctor, EctoDoctor.Test.MySQLRepo,
  username: "root",
  password: "",
  hostname: "localhost",
  database: "ecto_doctor_test"

config :ecto_doctor, EctoDoctor.Test.SQLiteRepo,
  database: Path.expand("../tmp/ecto_doctor_test.db", __DIR__)

config :logger, level: :warning
