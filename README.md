# Ecto Doctor

Your schemas say one thing and your database says another. Ecto Doctor finds where they disagree.

It reads your Ecto schemas, changesets, the live database and then compares them.

It also catches N+1 queries while your tests run.

## Install

Add the dependency and run the installer.

```elixir
{:ecto_doctor, "~> 0.0.1", only: [:dev, :test], runtime: false}
```

```bash
mix deps.get
mix ecto_doctor.install
```

The installer turns on stack traces for your repos by adding this line to `config/dev.exs` and `config/test.exs`.

```elixir
config :my_app, MyApp.Repo, stacktrace: true
```

It starts N+1 detection at the end of `test/test_helper.exs`.

```elixir
EctoDoctor.RepeatedQueries.attach(repo: MyApp.Repo)
```

Then it scans every test from the `setup` in `test/support/data_case.ex` and `test/support/conn_case.ex`.

```elixir
setup tags do
  :ok = EctoDoctor.RepeatedQueries.scan_test(tags)
  MyApp.DataCase.setup_sandbox(tags)
  :ok
end
```

## Check your schemas

```bash
mix ecto.doctor
```

It exits with status 1 on an error so it works in CI without any setup.

`--format sarif` shows findings on pull request lines through GitHub code scanning.

`--fix` writes migrations for the findings a migration can fix and `--fix --apply` runs them after you confirm.

| Check | What it finds |
| --- | --- |
| `unhandled_constraint` | A database constraint no changeset handles so bad input crashes instead of showing a form error. |
| `string_length_overflow` | A string cast into a column with a length limit and no `validate_length`. |
| `enum_mismatch` | `Ecto.Enum` values that differ from the database enum or check constraint. |
| `type_mismatch` | A field whose type doesn't fit its column, or that has no column. |
| `unique_without_index` | A `unique_constraint` with no unique index behind it so duplicates get in. |
| `missing_not_null` | A required field whose column allows NULL. |
| `unindexed_foreign_key` | A `belongs_to` column with no index. |
| `missing_foreign_key` | A `belongs_to` column with no foreign key constraint. |
| `mismatched_key_type` | A foreign key whose type differs from the key it points to. |
| `on_delete_mismatch` | A `has_many` `on_delete` that disagrees with the foreign key. |
| `redundant_index` | An index another index already covers. |
| `orphan_table` | A table no schema points to. |
| `sequential_scans` | A large table read mostly by sequential scans. |
| `slow_queries` | Queries that take 100 ms or more on average, with their plans. |

Run `mix ecto.doctor.explain unhandled_constraint` to read more about a check.

## Catch N+1 queries

A test that runs the same query again and again from one place fails and shows where the query came from.

Here's what it printed on the [TeslaMate](https://github.com/teslamate-org/teslamate) test suite.

```text
N+1 query in TeslaMate.LogChargingTest test geo-fencing calculates the charge costs based on the price per kwh. It ran 4 times in 1.2 ms from TeslaMate.Log.recalculate_efficiency/3 at lib/teslamate/log.ex:917.
  SELECT ROUND(((c0."charge_energy_added" / NULLIF((c0."end_rated_range_km" - c0."start_rated_range_km"), 0)))::numeric, $1)::float8, count(*) FROM "charging_processes" AS c0 WHERE ((((((c0."car_id" = $2) AND (c0."duration_min" > 10)) AND (c0."end_battery_level" <= 95)) AND NOT (c0."end_rated_range_km" IS NULL)) AND NOT (c0."start_rated_range_km" IS NULL)) AND (c0."charge_energy_added" > 0.0)) GROUP BY 1 ORDER BY 2 DESC LIMIT 1
  lib/teslamate/repo.ex:2 TeslaMate.Repo.one/2
  lib/teslamate/log.ex:917 TeslaMate.Log.recalculate_efficiency/3
  lib/teslamate/log.ex:755 TeslaMate.Log.complete_charging_process/1
  test/teslamate/log/log_charging_test.exs:51 TeslaMate.LogChargingTest.log_charging_process/2
  test/teslamate/log/log_charging_test.exs:403 TeslaMate.LogChargingTest.test geo-fencing calculates the charge costs based on the price per kwh/1
  Run this query once and reuse the result instead of running it on every pass.
```

The function ran the same query for each rounding precision it tried so a possible fix loads the rows once and rounds them in Elixir.

```elixir
# Before: a query for each precision
for precision <- [5, 4, 3, 2] do
  Repo.one(most_common_factor_query(car, precision))
end

# After: one query and the rounding happens in Elixir
factors = Repo.all(factors_query(car))

for precision <- [5, 4, 3, 2] do
  Enum.frequencies_by(factors, &Decimal.round(&1, precision))
end
```

With that change the tests still pass and the finding goes away.

It watches every read query from any code and counts repeats within one test, request, LiveView event or Oban job.

If your app already has N+1 queries, record them once so only new ones fail.

```bash
ECTO_DOCTOR_RECORD=1 mix test
```

To check one block of code, use the assertions.

```elixir
import EctoDoctor.RepeatedQueries.Assertions

assert_no_repeated_queries(fn -> get(conn, ~p"/posts") end)
```

In dev the Plug shows the page's N+1 queries in a footer and in the browser console.

```elixir
if Application.compile_env(:my_app, :dev_routes) do
  plug EctoDoctor.Plug
end
```

It shows nothing until N+1 detection is attached, so attach it when the app starts in dev.

```elixir
# lib/my_app/application.ex in start/2
if Application.get_env(:my_app, :dev_routes) == true and
     Code.ensure_loaded?(EctoDoctor.RepeatedQueries) do
  EctoDoctor.RepeatedQueries.attach(repo: MyApp.Repo)
end
```

## Configure

`mix ecto.doctor` reads `.ecto_doctor.exs` if you have one.

```elixir
[
  checks: [orphan_table: [ignore: ["legacy_*"]], string_length_overflow: false],
  ignore_tables: ["schema_migrations", "oban_*"]
]
```

A schema can turn checks off for itself with a comment like `# ecto_doctor:ignore missing_not_null` inside its module.

`mix ecto.doctor.baseline` records today's findings so CI fails only on new ones.

## Databases

Ecto Doctor works with PostgreSQL 15, MySQL 8.4, MariaDB 10.11, SQLite 3.35 and anything newer.

It skips views, partitions, SQLite virtual tables, tables that extensions own and column types it doesn't know such as PostGIS or pgvector ones.

A custom Ecto type named after its column type counts as a match so `:vector` on a `vector` column is fine.

On SQLite it leaves out unhandled foreign keys since SQLite never says which key failed.

## How it compares

These Ecto libraries cover nearby ground and work well next to Ecto Doctor.

- [ecto_psql_extras](https://hex.pm/packages/ecto_psql_extras) reads PostgreSQL health such as bloat and cache hits but doesn't look at your schemas.
- [excellent_migrations](https://hex.pm/packages/excellent_migrations) checks your migrations for changes that are unsafe to deploy.

## License

MIT
