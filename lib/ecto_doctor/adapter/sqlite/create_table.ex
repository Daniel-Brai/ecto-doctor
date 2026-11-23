defmodule EctoDoctor.Adapter.SQLite.CreateTable do
  @moduledoc false

  # SQLite keeps a table's checks only in the CREATE TABLE statement that made the table
  # The statement is split into tokens so a CHECK inside a quoted name or string is never read as one

  @word_characters Enum.concat([?a..?z, ?A..?Z, ?0..?9, [?_, ?$]])
  @spaces [?\s, ?\t, ?\n, ?\r]
  @quotes [?", ?', ?`]

  @type check :: %{name: nil | String.t(), expression: String.t(), identifiers: [String.t()]}

  @doc "Reads every check in a CREATE TABLE statement with its name and the names it mentions."
  @spec checks(String.t()) :: [check()]
  def checks(sql) do
    sql
    |> tokens([])
    |> find_checks([], [])
  end

  defp find_checks([], _before, checks), do: Enum.reverse(checks)

  defp find_checks([{:word, word} = token | rest], before, checks) do
    case {String.upcase(word), drop_spaces(rest)} do
      {"CHECK", [{:open, _text} | inside]} ->
        {expression, rest} = group(inside, 1, [])
        check = build_check(before, expression)
        find_checks(rest, [], [check | checks])

      _other ->
        find_checks(rest, [token | before], checks)
    end
  end

  defp find_checks([token | rest], before, checks),
    do: find_checks(rest, [token | before], checks)

  defp build_check(before, expression) do
    %{
      name: constraint_name(Enum.reject(before, &space?/1)),
      expression: expression |> text() |> String.trim(),
      identifiers: identifiers(expression)
    }
  end

  # Strings in single quotes are values while words and double quoted text can be column names
  defp identifiers(expression) do
    expression
    |> Enum.filter(fn {kind, _text} -> kind in [:word, :quoted] end)
    |> Enum.map(fn {_kind, text} -> unquote_name(text) end)
  end

  # A named check reads CONSTRAINT name CHECK (...) so the name is the token right before CHECK
  defp constraint_name([name, {:word, keyword} | _rest]) do
    if String.upcase(keyword) == "CONSTRAINT", do: unquote_name(elem(name, 1))
  end

  defp constraint_name(_before), do: nil

  defp group([], _depth, acc), do: {Enum.reverse(acc), []}
  defp group([{:close, _text} | rest], 1, acc), do: {Enum.reverse(acc), rest}

  defp group([{:close, _text} = token | rest], depth, acc),
    do: group(rest, depth - 1, [token | acc])

  defp group([{:open, _text} = token | rest], depth, acc),
    do: group(rest, depth + 1, [token | acc])

  defp group([token | rest], depth, acc), do: group(rest, depth, [token | acc])

  defp text(tokens), do: Enum.map_join(tokens, fn {_kind, text} -> text end)

  defp drop_spaces(tokens), do: Enum.drop_while(tokens, &space?/1)

  defp space?({kind, _text}), do: kind == :space

  # A quoted name doubles any quote mark inside it
  defp unquote_name(<<mark, rest::binary>>) when mark in [?", ?`] do
    rest
    |> String.slice(0..-2//1)
    |> String.replace(<<mark, mark>>, <<mark>>)
  end

  defp unquote_name(text), do: text

  defp tokens(<<>>, acc), do: Enum.reverse(acc)
  defp tokens(<<"(", rest::binary>>, acc), do: tokens(rest, [{:open, "("} | acc])
  defp tokens(<<")", rest::binary>>, acc), do: tokens(rest, [{:close, ")"} | acc])

  defp tokens(<<mark, rest::binary>>, acc) when mark in @quotes do
    {text, rest} = quoted(rest, mark, <<mark>>)
    kind = if mark == ?', do: :string, else: :quoted
    tokens(rest, [{kind, text} | acc])
  end

  defp tokens(<<char, _rest::binary>> = sql, acc) when char in @word_characters do
    {word, rest} = take_word(sql, "")
    tokens(rest, [{:word, word} | acc])
  end

  defp tokens(<<char, _rest::binary>> = sql, acc) when char in @spaces do
    {space, rest} = take_spaces(sql, "")
    tokens(rest, [{:space, space} | acc])
  end

  defp tokens(<<char::utf8, rest::binary>>, acc),
    do: tokens(rest, [{:other, <<char::utf8>>} | acc])

  defp quoted(<<>>, _quote, acc), do: {acc, ""}

  defp quoted(<<mark, mark, rest::binary>>, mark, acc),
    do: quoted(rest, mark, acc <> <<mark, mark>>)

  defp quoted(<<mark, rest::binary>>, mark, acc), do: {acc <> <<mark>>, rest}

  defp quoted(<<char::utf8, rest::binary>>, mark, acc),
    do: quoted(rest, mark, acc <> <<char::utf8>>)

  defp take_word(<<char, rest::binary>>, acc) when char in @word_characters,
    do: take_word(rest, acc <> <<char>>)

  defp take_word(rest, acc), do: {acc, rest}

  defp take_spaces(<<char, rest::binary>>, acc) when char in @spaces,
    do: take_spaces(rest, acc <> <<char>>)

  defp take_spaces(rest, acc), do: {acc, rest}
end
