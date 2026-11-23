defmodule EctoDoctor.Test.Feed do
  alias EctoDoctor.Test.Repo
  alias EctoDoctor.Test.User

  def authors(posts) do
    posts
    |> Enum.map(&Repo.get(User, &1.user_id))
    |> Enum.uniq()
  end

  def comments(posts) do
    posts
    |> Enum.map(fn post -> post |> Ecto.assoc(:comments) |> Repo.all() end)
    |> List.flatten()
  end

  def comments_one_by_one(posts) do
    Enum.flat_map(posts, fn post -> Repo.preload(post, :comments).comments end)
  end

  def preloaded_authors(posts) do
    posts
    |> Repo.preload(:user)
    |> Enum.map(& &1.user)
  end
end
