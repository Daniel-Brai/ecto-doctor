defmodule Shop.FieldsFromFunction do
  def changeset(item, attrs), do: cast(item, attrs, fields())
end

defmodule Shop.WordList do
  def changeset(item, attrs), do: cast(item, attrs, ~w[name price]a)
end

defmodule Shop.AttributeMinusList do
  @fields [:name, :price, :sku]

  def changeset(item, attrs), do: cast(item, attrs, @fields -- [:sku])
end

defmodule Shop.ListWithAttributeTail do
  @extra [:sku]

  def changeset(item, attrs), do: cast(item, attrs, [:name | @extra])
end

defmodule Shop.Item.Changeset do
  alias Shop.Item

  def changeset(%Item{} = item, attrs), do: unique_constraint(item, :sku)
end

defmodule Shop.Quiet do
  # ecto_doctor:ignore missing_not_null, enum_mismatch

  defmodule Inner do
  end
end

defmodule Shop.OneLine, do: def(changeset(item, attrs), do: Ecto.Changeset.cast(item, attrs, [:name]))

defmodule Shop.Parent do
  defmodule __MODULE__.Child do
    def changeset(child, attrs), do: Ecto.Changeset.cast(child, attrs, [:name])
  end
end
