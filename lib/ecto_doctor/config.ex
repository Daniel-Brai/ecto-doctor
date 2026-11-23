defmodule EctoDoctor.Config do
  @moduledoc false

  alias EctoDoctor.Error

  @check_ids Enum.map(EctoDoctor.Checks.all(), & &1.id())

  @schema NimbleOptions.new!(
            apps: [
              type: {:list, :atom},
              doc: "Picks the apps whose schemas are checked. Defaults to the repo's app."
            ],
            only: [
              type: {:list, {:in, @check_ids}},
              doc: "Runs only these checks."
            ],
            except: [
              type: {:list, {:in, @check_ids}},
              default: [],
              doc: "Skips these checks."
            ],
            all: [
              type: :boolean,
              default: false,
              doc: "Reports info level findings too."
            ],
            checks: [
              type: {:custom, __MODULE__, :check_options, []},
              default: [],
              doc:
                "Sets options for single checks. `false` turns a check off and `ignore` takes table or column patterns."
            ],
            ignore_tables: [
              type: {:list, :string},
              default: ["schema_migrations", "oban_*"],
              doc: "Leaves these tables out of every check. One `*` matches anything."
            ],
            baseline: [
              type: {:or, [:string, nil]},
              default: EctoDoctor.Baseline.default_path(),
              doc:
                "Leaves out the findings listed in this file. Set it to nil to report everything."
            ]
          )

  # A misspelled check would turn nothing off and still pass
  @doc false
  @spec check_options(term()) :: {:ok, keyword()} | {:error, String.t()}
  def check_options(options) when is_list(options) do
    case Keyword.keys(options) -- @check_ids do
      [] ->
        {:ok, options}

      unknown ->
        {:error,
         "unknown checks #{inspect(unknown)} in :checks, valid checks are #{inspect(@check_ids)}"}
    end
  end

  def check_options(options),
    do: {:error, "expected :checks to be a keyword list, got #{inspect(options)}"}

  @spec docs() :: String.t()
  def docs, do: NimbleOptions.docs(@schema)

  @spec validate(keyword()) :: {:ok, keyword()} | {:error, Error.t()}
  def validate(opts) do
    case NimbleOptions.validate(opts, @schema) do
      {:ok, opts} -> {:ok, opts}
      {:error, error} -> {:error, %Error{message: Exception.message(error)}}
    end
  end

  @spec default_path() :: Path.t()
  def default_path, do: ".ecto_doctor.exs"

  @spec read_file(Path.t()) :: keyword()
  def read_file(path) do
    if File.exists?(path) do
      {opts, _binding} = Code.eval_file(path)
      opts
    else
      []
    end
  end
end
