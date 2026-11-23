defmodule EctoDoctor.Test.Catalog.Product do
  use Ecto.Schema

  alias Ecto.Changeset
  alias EctoDoctor.Test.Catalog.Brand
  alias EctoDoctor.Test.Catalog.Category
  alias EctoDoctor.Test.Catalog.Collection
  alias EctoDoctor.Test.Catalog.CollectionProduct
  alias EctoDoctor.Test.Catalog.Detail
  alias EctoDoctor.Test.Catalog.Dimensions
  alias EctoDoctor.Test.Catalog.Image
  alias EctoDoctor.Test.Catalog.Review
  alias EctoDoctor.Test.Catalog.Slug

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @required [:name, :slug, :price_cents]
  @optional [:tags, :attributes, :ratings, :status, :channels, :category_id, :maker_id]

  schema "products" do
    field :name, :string, source: :title
    field :slug, Slug
    field :price_cents, :integer
    field :tags, {:array, :string}
    field :attributes, :map
    field :ratings, {:map, :integer}
    field :status, Ecto.Enum, values: [draft: 0, live: 1]
    field :channels, {:array, Ecto.Enum}, values: [:web, :store]
    field :display_price, :string, virtual: true
    field :supplier_note, :string, redact: true, load_in_query: false
    field :maker_id, :string
    belongs_to :category, Category, type: :id
    belongs_to :brand, Brand, foreign_key: :maker_id, references: :code, define_field: false
    has_one :detail, Detail
    has_many :reviews, Review, where: [visible: true]
    has_many :archived_reviews, {"archived_reviews", Review}, on_delete: :delete_all
    has_many :reviewers, through: [:reviews, :author]
    many_to_many :collections, Collection, join_through: CollectionProduct
    embeds_one :dimensions, Dimensions, on_replace: :update
    embeds_many :images, Image
    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(%__MODULE__{} = product, attrs) do
    product
    |> Changeset.cast(attrs, @required ++ @optional)
    |> Changeset.cast_embed(:dimensions)
    |> Changeset.validate_required(@required)
    |> Changeset.validate_length(:name, max: 120)
    |> Changeset.validate_length(:slug, is: 12)
    |> Changeset.validate_length(:maker_id, max: 255)
    |> Changeset.unique_constraint(:slug)
    |> Changeset.unique_constraint([:category_id, :name], name: :products_category_id_title_index)
    |> Changeset.check_constraint(:price_cents, name: :price_cents_positive)
    |> Changeset.foreign_key_constraint(:category_id)
    |> Changeset.foreign_key_constraint(:maker_id)
  end
end
