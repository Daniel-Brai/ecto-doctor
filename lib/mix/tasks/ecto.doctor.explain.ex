defmodule Mix.Tasks.Ecto.Doctor.Explain do
  @shortdoc "Describes Ecto Doctor's checks"

  @moduledoc """
  Describes one check or lists them all.

      mix ecto.doctor.explain
      mix ecto.doctor.explain unhandled_constraint
  """

  use Mix.Task

  alias EctoDoctor.Check
  alias EctoDoctor.Checks

  @impl Mix.Task
  def run([]) do
    Enum.each(Checks.all(), fn check ->
      Mix.shell().info(String.pad_trailing(to_string(check.id()), 24) <> Check.summary(check))
    end)
  end

  def run([id | _]) do
    check = Enum.find(Checks.all(), fn check -> to_string(check.id()) == id end)

    case check do
      nil -> Mix.raise("There is no check named #{id}. Run mix ecto.doctor.explain to list them.")
      check -> Mix.shell().info(check.explain())
    end
  end
end
