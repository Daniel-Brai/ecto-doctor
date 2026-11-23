defmodule EctoDoctor.Test.Catalog.Slug do
  use Ecto.Type

  def type, do: :string

  def cast(slug) when is_binary(slug), do: {:ok, String.downcase(slug)}
  def cast(_slug), do: :error

  def load(slug), do: {:ok, slug}
  def dump(slug), do: {:ok, slug}
end
