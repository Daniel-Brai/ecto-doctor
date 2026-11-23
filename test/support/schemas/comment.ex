defmodule EctoDoctor.Test.Comment do
  use Ecto.Schema

  import Ecto.Changeset

  alias EctoDoctor.Test.Post

  schema "comments" do
    field :body, :string
    belongs_to :post, Post
    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(comment, attrs), do: cast(comment, attrs, [:body, :post_id])
end
