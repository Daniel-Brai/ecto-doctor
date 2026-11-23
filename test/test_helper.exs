alias Ecto.Adapters.SQL.Sandbox
alias EctoDoctor.RepeatedQueries
alias EctoDoctor.Test.Repo

{:ok, _pid} = Repo.start_link()
Sandbox.mode(Repo, :manual)

RepeatedQueries.attach(repo: Repo, log: false, baseline: "tmp/no_baseline.exs")

ExUnit.start(exclude: [:mysql])
