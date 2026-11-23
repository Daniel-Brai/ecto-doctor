defmodule EctoDoctor.Adapter.MySQLTest do
  use ExUnit.Case, async: false

  alias EctoDoctor.Test.MySQLRepo
  alias EctoDoctor.TestUtils

  @moduletag :mysql

  setup_all do
    {:ok, findings: TestUtils.diagnose_fresh!(MySQLRepo, "test/support/mysql/migrations")}
  end

  describe "read/2" do
    test "reads a varchar length", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :string_length_overflow, "books", ["title"])
      assert finding.fix == "|> validate_length(:title, max: 80)"
    end

    test "reads the values of an ENUM column", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :enum_mismatch, "books", ["format"])
      assert finding.message =~ ~s(rejects ["ebook"])
    end

    test "reads the columns of a check constraint", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :unhandled_constraint, "books", ["pages"])
    end

    test "returns no length limit for a TEXT column", %{findings: findings} do
      assert TestUtils.find(findings, :string_length_overflow, "books", ["notes"]) == []
    end

    test "reads a unique index", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :unhandled_constraint, "shelves", ["name"])
      assert finding.message =~ "shelves_name_index"
    end

    test "reads the on delete action of a foreign key", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :on_delete_mismatch, "books", ["shelf_id"])
      assert finding.message =~ "ON DELETE RESTRICT"
    end

    test "matches a handled foreign key by its name", %{findings: findings} do
      assert TestUtils.find(findings, :unhandled_constraint, "books", ["shelf_id"]) == []
    end
  end
end
