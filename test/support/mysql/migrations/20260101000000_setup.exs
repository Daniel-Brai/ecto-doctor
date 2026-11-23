defmodule EctoDoctor.Test.MySQLRepo.Migrations.Setup do
  use Ecto.Migration

  def change do
    create table(:shelves) do
      add :name, :string, size: 40
    end

    create unique_index(:shelves, [:name])

    create table(:books) do
      add :title, :string, size: 80
      add :format, :"ENUM('paperback','hardcover')"
      add :pages, :integer
      add :notes, :text
      add :shelf_id, references(:shelves, on_delete: :restrict)
    end

    create constraint(:books, :books_pages_positive, check: "pages > 0")
  end
end
