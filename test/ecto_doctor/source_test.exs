defmodule EctoDoctor.SourceTest do
  use ExUnit.Case, async: true

  alias EctoDoctor.Source
  alias EctoDoctor.TestUtils

  setup do
    {:ok, modules: Source.read(["test/fixtures/changesets.ex"])}
  end

  describe "read/1" do
    test "returns nothing for a file that doesn't parse" do
      assert Source.read(["test/fixtures/broken.ex"]) == %{}
    end

    test "returns unknown fields for a function call", %{modules: modules} do
      rule = TestUtils.only_rule!(modules, Shop.FieldsFromFunction)
      assert rule.fields == :unknown
    end

    test "reads a word list", %{modules: modules} do
      rule = TestUtils.only_rule!(modules, Shop.WordList)
      assert rule.fields == [:name, :price]
    end

    test "reads an attribute minus a list", %{modules: modules} do
      rule = TestUtils.only_rule!(modules, Shop.AttributeMinusList)
      assert rule.fields == [:name, :price]
    end

    test "reads a list with an attribute tail", %{modules: modules} do
      rule = TestUtils.only_rule!(modules, Shop.ListWithAttributeTail)
      assert rule.fields == [:name, :sku]
    end

    test "reads a module written on one line", %{modules: modules} do
      assert TestUtils.only_rule!(modules, Shop.OneLine).fields == [:name]
    end

    test "reads a module named with __MODULE__", %{modules: modules} do
      assert TestUtils.only_rule!(modules, Shop.Parent.Child).fields == [:name]
    end

    test "reads the checks an ignore comment turns off", %{modules: modules} do
      assert modules[Shop.Quiet].ignore == [:missing_not_null, :enum_mismatch]
    end

    test "keeps an ignore comment to the module it sits in", %{modules: modules} do
      assert modules[Shop.Quiet.Inner].ignore == []
    end

    test "links a changeset to the struct in its head", %{modules: modules} do
      rule = TestUtils.only_rule!(modules, Shop.Item.Changeset)
      assert rule.struct == Shop.Item
    end
  end
end
