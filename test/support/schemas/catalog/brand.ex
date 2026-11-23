defmodule EctoDoctor.Test.Catalog.Brand do
  use Ecto.Schema

  @primary_key {:code, :string, autogenerate: false}

  schema "brands" do
    field :name, :string
  end
end
