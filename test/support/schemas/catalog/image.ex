defmodule EctoDoctor.Test.Catalog.Image do
  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :url, :string
  end
end
