defmodule EctoDoctor.Test.Post do
  use Ecto.Schema

  import Ecto.Changeset

  alias EctoDoctor.Test.Comment
  alias EctoDoctor.Test.User

  schema "posts" do
    field :title, :string
    field :slug, :string
    field :legacy_score, :integer
    belongs_to :user, User
    belongs_to :editor, User
    has_many :comments, Comment, on_delete: :delete_all
    many_to_many :readers, User, join_through: "post_readers"
    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :slug, :user_id])
    |> validate_length(:title, max: 200)
    |> unique_constraint(:slug)
    |> unique_constraint(:title)
    |> foreign_key_constraint(:user_id)
  end
end
