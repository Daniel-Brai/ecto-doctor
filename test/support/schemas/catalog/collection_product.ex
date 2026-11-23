defmodule EctoDoctor.Test.Catalog.CollectionProduct do
  use Ecto.Schema

  alias EctoDoctor.Test.Catalog.Collection
  alias EctoDoctor.Test.Catalog.Product

  @primary_key false

  schema "collection_products" do
    belongs_to :collection, Collection, primary_key: true
    belongs_to :product, Product, type: :binary_id, primary_key: true
  end
end
