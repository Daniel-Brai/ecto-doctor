defmodule EctoDoctor.Test.SQLiteRepo do
  use Ecto.Repo, otp_app: :ecto_doctor, adapter: Ecto.Adapters.SQLite3
end
