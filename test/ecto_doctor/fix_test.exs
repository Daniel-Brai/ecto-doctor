defmodule EctoDoctor.FixTest do
  use EctoDoctor.DataCase, async: true

  alias EctoDoctor.Fix
  alias EctoDoctor.Test.Repo
  alias EctoDoctor.TestUtils

  @moduletag :tmp_dir

  setup do
    {:ok, findings: TestUtils.diagnose!(only: [:unindexed_foreign_key, :missing_not_null])}
  end

  describe "write_migrations/3" do
    test "writes one migration per phase in the order they run", %{
      tmp_dir: dir,
      findings: findings
    } do
      names = Enum.map(Fix.write_migrations(Repo, findings, dir), &Path.basename/1)

      assert Enum.map(names, &String.slice(&1, 15..-1//1)) ==
               ~w[ecto_doctor_indexes.exs ecto_doctor_constraints.exs ecto_doctor_validations.exs]
    end

    test "builds indexes outside a transaction", %{tmp_dir: dir, findings: findings} do
      [indexes | _rest] = Fix.write_migrations(Repo, findings, dir)
      assert String.contains?(File.read!(indexes), "@disable_ddl_transaction true")
    end
  end
end
