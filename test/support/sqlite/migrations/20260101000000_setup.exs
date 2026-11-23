defmodule EctoDoctor.Test.SQLiteRepo.Migrations.Setup do
  use Ecto.Migration

  def change do
    create table(:shelves) do
      add :name, :"VARCHAR(40)"
    end

    create unique_index(:shelves, [:name])

    create table(:books) do
      add :title, :"VARCHAR(80)"

      add :format, :string,
        check: %{name: "books_format_check", expr: "format in ('paperback', 'hardcover')"}

      add :pages, :integer, check: %{name: "books_pages_positive", expr: "pages > 0"}
      add :notes, :text
      add :shelf_id, references(:shelves, on_delete: :restrict)
    end
  end
end
