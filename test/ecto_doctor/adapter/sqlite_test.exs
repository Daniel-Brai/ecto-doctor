defmodule EctoDoctor.Adapter.SQLiteTest do
  use ExUnit.Case, async: false

  alias EctoDoctor.Test.SQLiteRepo
  alias EctoDoctor.TestUtils

  setup_all do
    {:ok, findings: TestUtils.diagnose_fresh!(SQLiteRepo, "test/support/sqlite/migrations")}
  end

  describe "read/2" do
    test "returns no length limit since SQLite never enforces one", %{findings: findings} do
      assert TestUtils.find(findings, :string_length_overflow, "books", ["title"]) == []
    end

    test "reads the columns of a check constraint", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :unhandled_constraint, "books", ["pages"])
    end

    test "reads the values a check constraint allows", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :enum_mismatch, "books", ["format"])
      assert finding.message =~ ~s(rejects ["ebook"])
    end

    test "reads a unique index", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :unhandled_constraint, "shelves", ["name"])
      assert finding.message =~ "shelves_name_index"
    end

    test "reads a foreign key without an index", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :unindexed_foreign_key, "books", ["shelf_id"])
    end

    test "reads the on delete action of a foreign key", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :on_delete_mismatch, "books", ["shelf_id"])
      assert finding.message =~ "ON DELETE RESTRICT"
    end

    test "leaves out foreign keys no changeset can catch", %{findings: findings} do
      assert TestUtils.find(findings, :unhandled_constraint, "books", ["shelf_id"]) == []
    end
  end
end
