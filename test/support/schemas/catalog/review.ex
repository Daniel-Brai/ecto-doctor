defmodule EctoDoctor.Test.Catalog.Review do
  use Ecto.Schema

  alias EctoDoctor.Test.Catalog.Product
  alias EctoDoctor.Test.User

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 4]}

  schema "reviews" do
    field :body, :string
    field :visible, :boolean
    belongs_to :product, Product, type: :binary_id
    belongs_to :author, User
  end
end
