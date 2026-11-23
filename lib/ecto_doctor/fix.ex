defmodule EctoDoctor.Fix do
  @moduledoc false

  alias EctoDoctor.Finding

  @phases [concurrent: "Indexes", add: "Constraints", validate: "Validations"]

  # Building an index concurrently can't run inside a transaction or the migration lock
  @concurrent_attributes ["@disable_ddl_transaction true", "@disable_migration_lock true"]

  @doc "Writes one migration per phase into the directory and returns their paths in the order they run."
  @spec write_migrations(Ecto.Repo.t(), [Finding.t()], Path.t()) :: [Path.t()]
  def write_migrations(repo, findings, dir) do
    steps = Enum.flat_map(findings, & &1.migration)
    now = DateTime.utc_now()

    @phases
    |> Enum.map(fn {phase, name} ->
      %{phase: phase, name: name, lines: phase_lines(steps, phase)}
    end)
    |> Enum.reject(&(&1.lines == []))
    |> Enum.with_index()
    |> Enum.map(fn {migration, index} ->
      stamp = now |> DateTime.add(index) |> Calendar.strftime("%Y%m%d%H%M%S")
      write(dir, repo, Map.put(migration, :stamp, stamp))
    end)
  end

  @doc "Runs only these migrations, never other pending ones."
  @spec apply_migrations(Ecto.Repo.t(), [Path.t()]) :: :ok
  def apply_migrations(repo, paths) do
    Enum.each(paths, fn path ->
      [{module, _binary}] = Code.compile_file(path)
      Ecto.Migrator.up(repo, version(path), module)
    end)
  end

  defp phase_lines(steps, phase) do
    for {^phase, line} <- steps, do: line
  end

  defp version(path) do
    [stamp | _rest] = path |> Path.basename() |> String.split("_", parts: 2)
    String.to_integer(stamp)
  end

  defp write(dir, repo, migration) do
    path = Path.join(dir, "#{migration.stamp}_ecto_doctor_#{String.downcase(migration.name)}.exs")
    content = render(repo, migration)

    File.mkdir_p!(dir)
    File.write!(path, content, [:exclusive])

    path
  end

  defp render(repo, migration) do
    module = "#{inspect(repo)}.Migrations.EctoDoctor#{migration.name}#{migration.stamp}"

    lines =
      ["defmodule #{module} do", "  use Ecto.Migration", ""] ++
        attributes(migration.phase) ++
        ["  def change do"] ++
        Enum.map(migration.lines, &("    " <> &1)) ++
        ["  end", "end"]

    Enum.join(lines, "\n") <> "\n"
  end

  defp attributes(:concurrent), do: Enum.map(@concurrent_attributes, &("  " <> &1)) ++ [""]
  defp attributes(_phase), do: []
end
