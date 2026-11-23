defmodule EctoDoctor.Test.Repo.Migrations.Setup do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE user_status AS ENUM ('active', 'banned')", "DROP TYPE user_status"
    execute "CREATE SCHEMA billing", "DROP SCHEMA billing"

    create table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :role, :string
      add :status, :user_status
      add :links, {:array, :map}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create index(:users, [:email], name: :users_email_lookup_index)
    create constraint(:users, :users_role_check, check: "role IN ('admin', 'member')")

    create table(:posts) do
      add :user_id, references(:users)
      add :editor_id, :bigint
      add :title, :string
      add :slug, :string
      timestamps(type: :timestamptz)
    end

    create index(:posts, [:editor_id])
    create unique_index(:posts, [:slug])
    create constraint(:posts, :posts_title_length, check: "char_length(title) > 2")

    create table(:comments) do
      add :post_id, references(:posts, type: :integer)
      add :body, :text
      add :created_at, :utc_datetime_usec
    end

    create index(:comments, [:post_id])
    create index(:comments, [:post_id, :created_at])

    create table(:invoices, prefix: "billing", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, prefix: "public")
      add :number, :string
    end

    create index(:invoices, [:user_id], prefix: "billing")
    create unique_index(:invoices, [:number], prefix: "billing")

    create table(:post_readers, primary_key: false) do
      add :post_id, references(:posts, on_delete: :delete_all), primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
    end

    create table(:audit_logs) do
      add :message, :text
    end
  end
end
