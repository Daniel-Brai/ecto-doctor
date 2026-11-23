defmodule EctoDoctor.TestUtils do
  alias EctoDoctor.Test.Post
  alias EctoDoctor.Test.Repo
  alias EctoDoctor.Test.User
  alias Faker.Internet
  alias Faker.Lorem
  alias Faker.Person

  def insert_random_user!, do: Repo.insert!(%User{email: Internet.email(), name: Person.name()})

  def insert_random_posts!(%User{} = user, count) do
    Enum.map(1..count, fn _ -> Repo.insert!(%Post{title: Lorem.sentence(3), user_id: user.id}) end)
  end

  def find_one!(findings, check, table, columns) do
    [finding] = find(findings, check, table, columns)
    finding
  end

  def find(findings, check, table),
    do: Enum.filter(findings, &(&1.check == check and &1.table == table))

  def find(findings, check, table, columns),
    do: Enum.filter(find(findings, check, table), &(&1.columns == columns))

  def diagnose_fresh!(repo, migrations) do
    config = repo.config()
    repo.__adapter__().storage_down(config)
    :ok = repo.__adapter__().storage_up(config)

    {:ok, findings, _apps} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        Ecto.Migrator.run(repo, migrations, :up, all: true, log: false)
        {:ok, findings} = EctoDoctor.diagnose(repo, all: true, baseline: nil)
        findings
      end)

    findings
  end

  def diagnose!(opts \\ []) do
    {:ok, findings} = EctoDoctor.diagnose(Repo, Keyword.merge([all: true, baseline: nil], opts))
    findings
  end

  def only_rule!(modules, module) do
    [rule] = modules[module].rules
    rule
  end
end
