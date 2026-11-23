defmodule EctoDoctor.Test.Billing.Invoice do
  use Ecto.Schema

  alias EctoDoctor.Test.User

  @schema_prefix "billing"
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "invoices" do
    field :number, :string
    belongs_to :user, User
  end
end
