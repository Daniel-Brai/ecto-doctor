defmodule EctoDoctor.Test.Catalog.Detail do
  use Ecto.Schema

  alias EctoDoctor.Test.Catalog.Product

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7, precision: :monotonic]}
  @foreign_key_type :binary_id

  schema "product_details" do
    field :description, :string
    belongs_to :product, Product
  end
end
