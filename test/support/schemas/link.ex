defmodule EctoDoctor.Test.Link do
  use Ecto.Schema

  embedded_schema do
    field :label, :string
    field :url, :string
  end
end
