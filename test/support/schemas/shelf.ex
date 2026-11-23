defmodule EctoDoctor.Test.Shelf do
  use Ecto.Schema

  alias EctoDoctor.Test.Book

  schema "shelves" do
    field :name, :string
    has_many :books, Book, on_delete: :delete_all
  end
end
