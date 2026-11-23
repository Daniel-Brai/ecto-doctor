defmodule EctoDoctor.Source do
  @moduledoc false

  alias EctoDoctor.Checks
  alias EctoDoctor.Rule

  @ignore_comment "# ecto_doctor:ignore "

  @type info :: %{rules: [Rule.t()], ignore: [atom()], schema_line: nil | pos_integer()}

  @spec read([String.t()]) :: %{module() => info()}
  def read(files) do
    files
    |> Enum.flat_map(&read_file/1)
    |> Map.new()
  end

  defp read_file(file) do
    path = Path.relative_to_cwd(file)

    with {:ok, code} <- File.read(file),
         {:ok, ast, comments} <- parse(code, file) do
      modules = modules(ast, nil)

      for module <- modules do
        ignore = ignored_checks(comments, module, modules)
        {module.name, read_module(module.name, module.body, path, ignore)}
      end
    else
      _error -> []
    end
  end

  defp parse(code, file) do
    Code.string_to_quoted_with_comments(code, columns: true, token_metadata: true, file: file)
  end

  defp modules({:defmodule, meta, [{:__aliases__, _, parts}, [do: body]]}, parent) do
    case module_name(parent, parts) do
      nil ->
        []

      name ->
        module = %{name: name, body: body, lines: meta[:line]..last_line(meta)//1}
        [module | modules(body, name)]
    end
  end

  defp modules({:__block__, _meta, nodes}, parent) do
    Enum.flat_map(nodes, &modules(&1, parent))
  end

  defp modules(_node, _parent), do: []

  # defmodule __MODULE__.Nested sits inside its parent while a name built any other way needs compiling
  defp module_name(parent, [{:__MODULE__, _meta, _context} | rest]) when parent != nil do
    module_name(parent, rest)
  end

  defp module_name(parent, parts) do
    if Enum.all?(parts, &is_atom/1), do: Module.concat([parent | parts])
  end

  # A defmodule written on one line has no end so the module is just that line
  defp last_line(meta) do
    case Keyword.fetch(meta, :end) do
      {:ok, end_meta} -> end_meta[:line]
      :error -> meta[:line]
    end
  end

  # A comment like `# ecto_doctor:ignore missing_not_null` turns checks off for the module it sits in
  defp ignored_checks(comments, module, modules) do
    comments
    |> Enum.filter(&(innermost_module(modules, &1.line) == module))
    |> Enum.flat_map(&comment_checks(&1.text))
  end

  # A nested module is its own module so the smallest one around the line owns the comment
  defp innermost_module(modules, line) do
    modules
    |> Enum.filter(&(line in &1.lines))
    |> Enum.min_by(&Range.size(&1.lines), fn -> nil end)
  end

  defp comment_checks(@ignore_comment <> names) do
    ids = Map.new(Checks.all(), &{to_string(&1.id()), &1.id()})

    names
    |> String.split([",", " "], trim: true)
    |> Enum.map(&Map.get(ids, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp comment_checks(_text), do: []

  defp read_module(name, body, file, ignore) do
    state = %{
      module: name,
      file: file,
      aliases: %{},
      attributes: %{},
      head_struct: nil,
      rules: [],
      ignore: ignore,
      schema_line: nil
    }

    state = walk(body, state)

    %{rules: Enum.reverse(state.rules), ignore: state.ignore, schema_line: state.schema_line}
  end

  # A nested module is read on its own
  defp walk({:defmodule, _meta, _args}, state), do: state

  defp walk({:alias, _meta, [{:__aliases__, _, parts} | options]}, state) do
    case expand(parts, state.aliases) do
      nil -> state
      module -> put_in(state.aliases[alias_name(options, parts)], module)
    end
  end

  defp walk({:@, _meta, [{name, _, [value]}]}, state) when is_atom(name) do
    put_in(state.attributes[name], value)
  end

  defp walk({macro, meta, [source | _rest]} = node, state)
       when macro in [:schema, :typed_schema] and is_binary(source) do
    walk_children(node, %{state | schema_line: meta[:line]})
  end

  defp walk({kind, _meta, [head, body]}, state) when kind in [:def, :defp] do
    state = %{state | head_struct: head_struct(head, state.aliases)}
    state = walk(body, state)

    %{state | head_struct: nil}
  end

  defp walk({:|>, _meta, [left, {fun, meta, args} = right]}, state) when is_list(args) do
    state = walk(left, state)

    case rule_kind(fun) do
      nil -> walk(right, state)
      kind -> walk_children(args, add_rule(state, kind, meta, args))
    end
  end

  defp walk({fun, meta, [_changeset | args]} = node, state) when args != [] do
    case rule_kind(fun) do
      nil -> walk_children(node, state)
      kind -> walk_children(args, add_rule(state, kind, meta, args))
    end
  end

  defp walk(node, state), do: walk_children(node, state)

  defp walk_children({_name, _meta, args}, state) when is_list(args) do
    walk_children(args, state)
  end

  defp walk_children(nodes, state) when is_list(nodes), do: Enum.reduce(nodes, state, &walk/2)
  defp walk_children({left, right}, state), do: walk(right, walk(left, state))
  defp walk_children(_node, state), do: state

  defp rule_kind({:., _meta, [{:__aliases__, _, [:Changeset]}, fun]}), do: rule_kind(fun)
  defp rule_kind({:., _meta, [{:__aliases__, _, [:Ecto, :Changeset]}, fun]}), do: rule_kind(fun)

  defp rule_kind(fun) when is_atom(fun) do
    if fun in Rule.kinds(), do: fun
  end

  defp rule_kind(_fun), do: nil

  # cast takes params before the fields while the other calls take the fields first
  defp add_rule(state, :cast, meta, [_params | args]) when args != [] do
    put_rule(state, :cast, meta, args)
  end

  defp add_rule(state, :cast, _meta, _args), do: state
  defp add_rule(state, kind, meta, args), do: put_rule(state, kind, meta, args)

  defp put_rule(state, kind, meta, [fields | rest]) do
    rule = %Rule{
      kind: kind,
      fields: resolve(fields, state.attributes),
      opts: literal_options(List.first(rest)),
      module: state.module,
      struct: state.head_struct,
      schema: nil,
      file: state.file,
      line: meta[:line]
    }

    %{state | rules: [rule | state.rules]}
  end

  defp resolve(ast, attributes) do
    case resolve_fields(ast, attributes) do
      {:ok, fields} -> fields
      :error -> :unknown
    end
  end

  defp resolve_fields(field, _attributes) when is_atom(field), do: {:ok, [field]}

  defp resolve_fields({:sigil_w, _meta, [{:<<>>, _, [words]}, _modifiers]}, _attributes) do
    fields = words |> String.split() |> Enum.map(&String.to_atom/1)
    {:ok, fields}
  end

  defp resolve_fields({:@, _meta, [{name, _, context}]}, attributes) when is_atom(context) do
    case Map.fetch(attributes, name) do
      {:ok, value} -> resolve_fields(value, attributes)
      :error -> :error
    end
  end

  defp resolve_fields({:++, _meta, [left, right]}, attributes) do
    with {:ok, left} <- resolve_fields(left, attributes),
         {:ok, right} <- resolve_fields(right, attributes) do
      {:ok, left ++ right}
    end
  end

  defp resolve_fields({:--, _meta, [left, right]}, attributes) do
    with {:ok, left} <- resolve_fields(left, attributes),
         {:ok, right} <- resolve_fields(right, attributes) do
      {:ok, left -- right}
    end
  end

  defp resolve_fields(list, attributes) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn element, {:ok, fields} ->
      case resolve_element(element, attributes) do
        {:ok, more} -> {:cont, {:ok, fields ++ more}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp resolve_fields(_ast, _attributes), do: :error

  defp resolve_element({:|, _meta, [head, tail]}, attributes) do
    with {:ok, head} <- resolve_fields(head, attributes),
         {:ok, tail} <- resolve_fields(tail, attributes) do
      {:ok, head ++ tail}
    end
  end

  defp resolve_element(element, attributes), do: resolve_fields(element, attributes)

  # An option set from a variable or a call can't be read so it is kept as :unknown
  defp literal_options(options) when is_list(options) do
    options
    |> Enum.filter(fn option -> match?({key, _value} when is_atom(key), option) end)
    |> Enum.map(fn {key, value} -> {key, literal(value)} end)
  end

  defp literal_options(_options), do: []

  defp literal(value) when is_atom(value) or is_binary(value) or is_integer(value), do: value
  defp literal(_value), do: :unknown

  defp head_struct({:when, _meta, [head | _guards]}, aliases), do: head_struct(head, aliases)

  defp head_struct({_name, _meta, args}, aliases) when is_list(args) do
    Enum.find_value(args, &arg_struct(&1, aliases))
  end

  defp head_struct(_head, _aliases), do: nil

  defp arg_struct({:=, _meta, [{:%, _, [module, _fields]}, _var]}, aliases) do
    struct_module(module, aliases)
  end

  defp arg_struct({:=, _meta, [_var, {:%, _, [module, _fields]}]}, aliases) do
    struct_module(module, aliases)
  end

  defp arg_struct({:%, _meta, [module, _fields]}, aliases), do: struct_module(module, aliases)
  defp arg_struct(_arg, _aliases), do: nil

  defp struct_module({:__aliases__, _meta, parts}, aliases), do: expand(parts, aliases)
  defp struct_module(_module, _aliases), do: nil

  # A part like __MODULE__ can't be expanded without compiling so the alias is skipped
  defp expand([first | rest] = parts, aliases) do
    if Enum.all?(parts, &is_atom/1) do
      Module.concat([Map.get(aliases, first, first) | rest])
    end
  end

  defp alias_name([[as: {:__aliases__, _meta, parts}]], _parts), do: List.last(parts)
  defp alias_name(_options, parts), do: List.last(parts)
end
