defmodule EctoDoctor.Test.Repo.Migrations.Catalog do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :text
    end

    create table(:brands, primary_key: false) do
      add :code, :string, primary_key: true
      add :name, :text
    end

    create table(:products, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string, null: false
      add :slug, :string, size: 12, null: false
      add :price_cents, :integer, null: false
      add :tags, {:array, :text}
      add :attributes, :map
      add :ratings, :map
      add :status, :integer
      add :channels, {:array, :text}
      add :supplier_note, :text
      add :maker_id, references(:brands, column: :code, type: :string)
      add :category_id, references(:categories, on_delete: :nilify_all)
      add :dimensions, :map
      add :images, :map
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index(:products, [:slug])
    create unique_index(:products, [:category_id, :title])
    create index(:products, [:maker_id])
    create constraint(:products, :price_cents_positive, check: "price_cents > 0")
    create constraint(:products, :products_status_check, check: "status IN (0, 1)")
    create index(:products, [:tags], using: :gin)
    create index(:products, [:tags], name: :products_tags_btree_index)

    create table(:product_details, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :description, :text
      add :product_id, references(:products, type: :uuid)
    end

    create index(:product_details, [:product_id])

    create table(:reviews, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :body, :text
      add :visible, :boolean
      add :product_id, references(:products, type: :uuid)
      add :author_id, references(:users)
    end

    create index(:reviews, [:product_id])
    create index(:reviews, [:author_id])

    create table(:archived_reviews, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :body, :text
      add :visible, :boolean
      add :product_id, references(:products, type: :uuid, on_delete: :delete_all)
      add :author_id, references(:users)
    end

    create index(:archived_reviews, [:product_id])
    create index(:archived_reviews, [:author_id])

    create table(:collections) do
      add :title, :text
    end

    create table(:collection_products, primary_key: false) do
      add :collection_id, references(:collections), primary_key: true
      add :product_id, references(:products, type: :uuid), primary_key: true
    end

    create index(:collection_products, [:product_id])
  end
end
