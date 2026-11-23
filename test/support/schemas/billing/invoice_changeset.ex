defmodule EctoDoctor.Test.Billing.Invoice.Changeset do
  import Ecto.Changeset

  alias EctoDoctor.Test.Billing.Invoice

  @fields ~w[number user_id]a

  def changeset(%Invoice{} = invoice, attrs) do
    invoice
    |> cast(attrs, @fields)
    |> validate_length(:number, max: 255)
    |> unique_constraint(:number)
    |> foreign_key_constraint(:user_id)
  end
end
