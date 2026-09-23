# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.KeyNamesTest do
  @moduledoc """
  Regression coverage for issue #77: one return type from `internal_key/2`.

  It used to return an atom when `String.to_existing_atom/1` found one and a
  string when it did not, so one parsed map held `:retry_count` beside
  `"created_by"` and which it held depended on the modules the VM had loaded
  rather than on the request. The tests below intern an atom themselves and
  then assert the type, so they measure the branch rather than waiting for a
  dependency to intern the right word.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Rpc.KeyNames
  alias AshKotlinMultiplatform.Test.Todo

  @config %{}

  defp intern(name) do
    _ = String.to_atom(name)
    name
  end

  defp unknown(prefix), do: "#{prefix}#{System.unique_integer([:positive])}Zz"

  describe "internal_key/2" do
    test "returns a string for a name the VM has interned" do
      name = intern("key_names_interned_probe")

      assert KeyNames.internal_key(name, nil) == "key_names_interned_probe"
      assert KeyNames.internal_key(name, Todo) == "key_names_interned_probe"
    end

    test "returns a string for a name the VM has never interned" do
      name = unknown("keyNamesUnknownProbe")

      assert is_binary(KeyNames.internal_key(name, nil))
      assert is_binary(KeyNames.internal_key(name, Todo))
    end

    test "returns a string for a name the resource declares" do
      assert KeyNames.internal_key("metadata", Todo) == "metadata"
      assert KeyNames.internal_key("dueDate", Todo) == "due_date"
    end

    test "interning a name does not change what it returns" do
      name = unknown("keyNamesStabilityProbe")
      before = KeyNames.internal_key(name, Todo)
      _ = String.to_atom(KeyNames.snake_case(name))

      assert KeyNames.internal_key(name, Todo) == before
    end

    test "mints no atom for an unknown name" do
      name = unknown("keyNamesNoMintProbe")
      atoms_before = :erlang.system_info(:atom_count)

      _ = KeyNames.internal_key(name, Todo)

      assert :erlang.system_info(:atom_count) == atoms_before
    end
  end

  describe "parse/3" do
    test "every key of a parsed map is a string, interned or not" do
      interned = intern("parse_interned_probe")
      fresh = unknown("parseFreshProbe")

      parsed =
        KeyNames.parse(
          %{"title" => "t", interned => 1, fresh => 2, "nested" => %{interned => 3}},
          Todo,
          @config
        )

      assert Enum.all?(Map.keys(parsed), &is_binary/1)
      assert Enum.all?(Map.keys(parsed["nested"]), &is_binary/1)
    end

    test "an untyped map attribute keeps its data keys as strings" do
      interned = intern("parse_untyped_probe")

      parsed = KeyNames.parse(%{"metadata" => %{interned => 1}}, Todo, @config)

      assert parsed == %{"metadata" => %{"parse_untyped_probe" => 1}}
    end
  end

  describe "resolve/2" do
    test "replaces a key that names one of the known names with that atom" do
      assert KeyNames.resolve(%{"limit" => 2}, [:limit, :offset]) == %{limit: 2}
    end

    test "leaves a key that names none of them the string it is" do
      name = intern("resolve_interned_probe")

      assert KeyNames.resolve(%{name => 2}, [:limit]) == %{name => 2}
    end

    test "leaves a key that is already an atom alone" do
      assert KeyNames.resolve(%{limit: 2}, [:limit]) == %{limit: 2}
    end
  end
end
