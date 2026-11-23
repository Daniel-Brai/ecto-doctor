defmodule EctoDoctor.Test.Catalog.Collection do
  use Ecto.Schema

  alias EctoDoctor.Test.Catalog.Product

  schema "collections" do
    field :title, :string
    many_to_many :products, Product, join_through: "collection_products"
  end
end
