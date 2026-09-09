# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerAtomSafetyTest do
  @moduledoc """
  Regression coverage for issue #18, through `Runner.run_action/3`.

  The runner called `String.to_atom/1` on client-supplied strings in three
  places: the `fields` list, the extraction template built from it, and
  `convert_keys_to_atoms/1`, which walks `input`, `filter`, `page` and
  `identity` recursively. The atom table is never garbage collected, so a caller
  looping on fresh names filled it and took the node down. The default
  controller requires authentication, so the blast radius is any authenticated
  user; an app that sets `require_auth: false` makes it unauthenticated.

  These cases assert on `:erlang.system_info(:atom_count)`, so the module is
  synchronous — a concurrent module compiling or resolving atoms would move
  that number.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Rpc.Runner

  @batch_size 500

  defp run(params) do
    Runner.run_action(:ash_kotlin_multiplatform, params)
  end

  defp atom_exists?(name) when is_binary(name) do
    _ = String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end

  defp unknown_name(prefix), do: "#{prefix}#{System.unique_integer([:positive])}Zz"

  # A name is only safe if neither the camelCase wire form nor the snake_case
  # internal form gained an atom — the old code minted the latter.
  defp refute_atoms_for(name) do
    refute atom_exists?(name)
    refute atom_exists?(Macro.underscore(name))
  end

  # A warm-up batch runs first: Ash's own lazy initialisation mints a few
  # hundred atoms the first time a path runs, and only then does the count
  # settle. Every batch after that must add exactly zero, which is what
  # separates a fixed path from one minting an atom per name.
  defp assert_no_atoms_minted(fun) do
    run_batch(fun, "atomBombWarmup")

    before = :erlang.system_info(:atom_count)
    names = run_batch(fun, "atomBombBatch")

    assert :erlang.system_info(:atom_count) == before
    Enum.each(names, &refute_atoms_for/1)
  end

  defp run_batch(fun, prefix) do
    for _ <- 1..@batch_size do
      name = unknown_name(prefix)
      fun.(name)
      name
    end
  end

  describe "the fields list" do
    test "a batch of unknown field names mints no atoms" do
      assert_no_atoms_minted(fn name ->
        run(%{"action" => "list_authors", "fields" => [name]})
      end)
    end

    test "a batch of unknown nested field names mints no atoms" do
      assert_no_atoms_minted(fn name ->
        run(%{"action" => "list_authors", "fields" => [%{name => [name]}]})
      end)
    end

    test "an unknown field name returns a clean error rather than crashing" do
      response = run(%{"action" => "list_authors", "fields" => ["noSuchFieldAnywhere"]})

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "unknown_field"
    end
  end

  describe "input, filter and page" do
    test "a batch of unknown input keys mints no atoms" do
      assert_no_atoms_minted(fn name ->
        run(%{
          "action" => "create_author",
          "input" => %{"name" => "Anon", "email" => "anon@example.com", name => "x"},
          "fields" => ["id"]
        })
      end)
    end

    test "a batch of unknown filter keys mints no atoms" do
      assert_no_atoms_minted(fn name ->
        run(%{"action" => "list_authors", "filter" => %{name => "x"}, "fields" => ["id"]})
      end)
    end

    test "a batch of unknown page keys mints no atoms" do
      assert_no_atoms_minted(fn name ->
        run(%{"action" => "list_authors", "page" => %{name => 10}, "fields" => ["id"]})
      end)
    end

    test "a batch of unknown identity keys mints no atoms" do
      assert_no_atoms_minted(fn name ->
        run(%{"action" => "list_books", "identity" => %{name => "x"}, "fields" => ["id"]})
      end)
    end

    test "a known camelCase input key still reaches the action" do
      assert %{"success" => true, "data" => author} =
               run(%{
                 "action" => "create_author",
                 "input" => %{"name" => "Susanna Clarke", "email" => "susanna@example.com"},
                 "fields" => ["id", "name"]
               })

      assert author["name"] == "Susanna Clarke"
    end
  end
end
