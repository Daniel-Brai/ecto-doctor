defmodule EctoDoctorTest do
  use EctoDoctor.DataCase, async: true

  alias EctoDoctor.Error
  alias EctoDoctor.Test.Repo
  alias EctoDoctor.TestUtils

  describe "diagnose/2 with options" do
    test "fails on a check name it doesn't know" do
      assert {:error, %Error{}} = EctoDoctor.diagnose(Repo, only: [:orphan_tables])
    end

    test "maps a column type to the family the types option names" do
      types = %{"character varying" => :integer}

      findings =
        TestUtils.diagnose!(only: [:type_mismatch], checks: [type_mismatch: [types: types]])

      assert [_finding] = TestUtils.find(findings, :type_mismatch, "posts", ["title"])
    end

    test "returns no info without all" do
      findings = TestUtils.diagnose!(all: false)
      assert Enum.all?(findings, &(&1.level != :info))
    end

    test "returns nothing for an ignored table" do
      findings = TestUtils.diagnose!(ignore_tables: ["audit_*"])
      assert TestUtils.find(findings, :orphan_table, "audit_logs") == []
    end

    test "runs only the checks asked for" do
      findings = TestUtils.diagnose!(only: [:missing_not_null])
      assert Enum.uniq(Enum.map(findings, & &1.check)) == [:missing_not_null]
    end
  end

  describe "diagnose/2" do
    setup do
      {:ok, findings: TestUtils.diagnose!()}
    end

    test "returns nothing for a changeset in another module", %{findings: findings} do
      assert TestUtils.find(findings, :unhandled_constraint, "billing.invoices") == []
    end

    test "returns nothing for a many_to_many join table", %{findings: findings} do
      assert TestUtils.find(findings, :orphan_table, "post_readers") == []
    end

    test "returns no errors or warnings for any kind of Ecto schema", %{findings: findings} do
      tables =
        ~w[categories brands products product_details reviews collections collection_products]

      assert Enum.filter(findings, &(&1.table in tables and &1.level != :info)) == []
    end

    test "returns nothing for a table an association names itself", %{findings: findings} do
      assert TestUtils.find(findings, :orphan_table, "archived_reviews") == []
    end

    test "keeps a GIN index next to a btree index on the same column", %{findings: findings} do
      assert TestUtils.find(findings, :redundant_index, "products", ["tags"]) == []
    end

    test "reports a plain index a unique index already covers", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :redundant_index, "users", ["email"])
    end

    test "returns nothing for a check on an enum column", %{findings: findings} do
      assert TestUtils.find(findings, :unhandled_constraint, "users", ["role"]) == []
    end

    test "returns nothing for an embed stored as an array", %{findings: findings} do
      assert TestUtils.find(findings, :type_mismatch, "users", ["links"]) == []
    end

    test "returns nothing for renamed timestamps without updated_at", %{findings: findings} do
      assert TestUtils.find(findings, :type_mismatch, "comments") == []
    end

    test "returns nothing for utc timestamps on timestamptz", %{findings: findings} do
      assert TestUtils.find(findings, :type_mismatch, "posts", ["inserted_at"]) == []
    end

    test "reports an unhandled unique index", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :unhandled_constraint, "users", ["email"])
      assert finding.fix == "|> unique_constraint(:email, name: \"users_email_index\")"
    end

    test "reports an unhandled check constraint", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :unhandled_constraint, "posts", ["title"])
    end

    test "reports an unhandled foreign key as a warning", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :unhandled_constraint, "comments", ["post_id"])
      assert finding.level == :warning
    end

    test "reports a string with no length limit", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :string_length_overflow, "users", ["name"])
      assert finding.fix == "|> validate_length(:name, max: 255)"
    end

    test "reports enum values the database lacks", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :enum_mismatch, "users", ["role"])
    end

    test "reports a field with no column", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :type_mismatch, "posts", ["legacy_score"])
    end

    test "reports timestamps that drop microseconds", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :type_mismatch, "users", ["inserted_at"])
    end

    test "reports a unique_constraint with no index", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :unique_without_index, "posts", ["title"])

      line =
        "create unique_index(:posts, [:title], name: \"posts_title_index\", concurrently: true)"

      assert finding.migration == [{:concurrent, line}]
    end

    test "reports a required field that allows null", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :missing_not_null, "users", ["name"])
      assert Enum.map(finding.migration, &elem(&1, 0)) == [:add, :validate, :validate, :validate]
    end

    test "reports a foreign key with no index", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :unindexed_foreign_key, "posts", ["user_id"])

      assert finding.migration == [
               {:concurrent, "create index(:posts, [:user_id], concurrently: true)"}
             ]
    end

    test "reports a belongs_to with no foreign key", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :missing_foreign_key, "posts", ["editor_id"])
    end

    test "reports a key type that differs", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :mismatched_key_type, "comments", ["post_id"])
    end

    test "reports an on_delete that differs", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :on_delete_mismatch, "comments", ["post_id"])
    end

    test "reports a redundant index", %{findings: findings} do
      finding = TestUtils.find_one!(findings, :redundant_index, "comments", ["post_id"])
      line = "drop index(:comments, [], name: \"comments_post_id_index\", concurrently: true)"
      assert finding.migration == [{:concurrent, line}]
    end

    test "reports a table with no schema", %{findings: findings} do
      assert [_finding] = TestUtils.find(findings, :orphan_table, "audit_logs", [])
    end
  end
end
