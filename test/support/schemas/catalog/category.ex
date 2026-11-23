defmodule EctoDoctor.Test.Catalog.Category do
  use Ecto.Schema

  alias EctoDoctor.Test.Catalog.Product

  schema "categories" do
    field :name, :string
    has_many :products, Product, on_delete: :nilify_all
  end
end
