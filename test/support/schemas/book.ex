defmodule EctoDoctor.Test.Book do
  use Ecto.Schema

  import Ecto.Changeset

  alias EctoDoctor.Test.Shelf

  schema "books" do
    field :title, :string
    field :format, Ecto.Enum, values: [:paperback, :hardcover, :ebook]
    field :pages, :integer
    field :notes, :string
    belongs_to :shelf, Shelf
  end

  def changeset(book, attrs) do
    book
    |> cast(attrs, [:title, :format, :pages, :notes, :shelf_id])
    |> validate_length(:title, min: 3)
    |> foreign_key_constraint(:shelf_id)
  end
end
