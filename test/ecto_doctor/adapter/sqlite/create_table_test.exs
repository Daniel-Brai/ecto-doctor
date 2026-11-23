defmodule EctoDoctor.Adapter.SQLite.CreateTableTest do
  use ExUnit.Case, async: true

  alias EctoDoctor.Adapter.SQLite.CreateTable

  describe "checks/1" do
    test "skips a CHECK inside a quoted string" do
      sql = ~S|CREATE TABLE "notes" ("body" TEXT DEFAULT 'CHECK (x > 1)')|
      assert CreateTable.checks(sql) == []
    end

    test "reads a check without a name" do
      sql = ~S|CREATE TABLE "books" ("pages" INTEGER CHECK (pages > (0)))|
      assert [%{name: nil, expression: "pages > (0)"}] = CreateTable.checks(sql)
    end
  end
end
