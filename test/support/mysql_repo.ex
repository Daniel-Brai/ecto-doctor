defmodule EctoDoctor.Test.MySQLRepo do
  use Ecto.Repo, otp_app: :ecto_doctor, adapter: Ecto.Adapters.MyXQL
end
