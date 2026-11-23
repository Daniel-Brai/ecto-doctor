defmodule EctoDoctor.Test.User do
  use Ecto.Schema

  import Ecto.Changeset

  alias EctoDoctor.Test.Link
  alias EctoDoctor.Test.Post

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: [:admin, :member, :guest]
    field :status, Ecto.Enum, values: [:active, :banned]
    embeds_many :links, Link
    has_many :posts, Post
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role])
    |> validate_required([:email, :name])
    |> validate_length(:email, max: 160)
  end
end
