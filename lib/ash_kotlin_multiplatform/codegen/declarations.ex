# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.Declarations do
  @moduledoc """
  Scans rendered Kotlin fragments for the top-level `class`, `interface`,
  `object` and `typealias` names they declare, and checks a whole file's
  worth of fragments for a name declared more than once.

  A "top-level" declaration sits at column 0 of the fragment. Every section
  generator emits its heredocs with the closing `\"\"\"` at the same
  indentation as the declaration line, so Elixir's heredoc dedent puts a
  genuine top-level declaration at column 0 and leaves a nested one (a union
  subclass, a companion object) indented. Checked against the real generated
  file for every current section, `PhoenixChannel` included: `names/1` finds
  exactly its 11 real top-level declarations and none of its nested union
  subclasses or companion object (#33).
  """

  @keyword_pattern ~r/\A
    (?:(?:public|internal|private|protected|abstract|open|final|sealed|data|value|inner|external|expect|actual|enum|fun)\s+)*
    (class|interface|object|typealias)
    \s+
    ([A-Za-z_][A-Za-z0-9_]*)
  /x

  @doc """
  Returns the top-level `class`, `interface`, `object` and `typealias` names
  declared in one Kotlin fragment.

  Column 0 only — annotations (`@Serializable`) and modifiers (`sealed`,
  `data`, `enum`, ...) on the same line as the keyword are allowed. A nested
  declaration (indented) is skipped, so a union's subclasses and a class's
  companion object never appear here.
  """
  def names(fragment) when is_binary(fragment) do
    fragment
    |> String.split("\n")
    |> Enum.flat_map(&line_name/1)
  end

  defp line_name(line) do
    case Regex.run(@keyword_pattern, line) do
      [_, _keyword, name] -> [name]
      nil -> []
    end
  end

  @doc """
  Checks a list of `{source, fragment}` pairs for a Kotlin identifier
  declared by more than one fragment.

  `source` is a short human-readable string identifying what produced the
  fragment (an attribute, a resource, an rpc_action, a typed query, or
  `"built-in"`), used only to build the error message.

  Returns `:ok`, or `{:error, message}` naming every clashing identifier and
  every source that declared it.
  """
  def check(sources_and_fragments) do
    clashes =
      sources_and_fragments
      |> Enum.flat_map(fn {source, fragment} ->
        fragment |> names() |> Enum.map(&{&1, source})
      end)
      |> Enum.group_by(fn {name, _source} -> name end, fn {_name, source} -> source end)
      |> Enum.filter(fn {_name, sources} -> length(sources) > 1 end)
      |> Enum.sort_by(fn {name, _sources} -> name end)

    case clashes do
      [] ->
        :ok

      clashes ->
        {:error, format_error(clashes)}
    end
  end

  defp format_error(clashes) do
    lines =
      Enum.map(clashes, fn {name, sources} ->
        source_lines = sources |> Enum.map(&"    #{&1}") |> Enum.join("\n")
        "#{name}:\n#{source_lines}"
      end)

    """
    Two or more Elixir sources generate the same Kotlin identifier:

    #{Enum.join(lines, "\n\n")}
    """
  end
end
