defmodule EctoDoctor.Test.Catalog.Dimensions do
  use Ecto.Schema

  embedded_schema do
    field :width, :integer
    field :height, :integer
  end
end
