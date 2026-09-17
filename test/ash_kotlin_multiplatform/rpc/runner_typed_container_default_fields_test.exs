# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerTypedContainerDefaultFieldsTest do
  @moduledoc """
  A generic action returning a struct, tuple or keyword list that declares its
  `fields` answers a request with no `fields` exactly as it answers one naming
  every field (#95).

  #88 gave a `:map` with declared fields that default and no other container.
  The rest fell back to the owning resource, so `book_stats` sent Book's five
  attribute names, every value nil.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  @all_fields ["bookCount", "topTitle"]

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  for {action, expected} <- [
        {"book_stats", %{"bookCount" => 2, "topTitle" => "Kindred"}},
        {"book_stats_all",
         [%{"bookCount" => 1, "topTitle" => "A"}, %{"bookCount" => 2, "topTitle" => "B"}]},
        {"book_pair", %{"bookCount" => 2, "topTitle" => "Kindred"}},
        {"book_pairs",
         [%{"bookCount" => 1, "topTitle" => "A"}, %{"bookCount" => 2, "topTitle" => "B"}]},
        {"book_options", %{"bookCount" => 2, "topTitle" => "Kindred"}},
        {"book_options_all",
         [%{"bookCount" => 1, "topTitle" => "A"}, %{"bookCount" => 2, "topTitle" => "B"}]}
      ] do
    test "#{action} with no fields sends every declared field" do
      assert run(%{"action" => unquote(action)}) ==
               %{"success" => true, "data" => unquote(Macro.escape(expected))}
    end

    test "#{action} with no fields matches naming every field" do
      assert run(%{"action" => unquote(action)}) ==
               run(%{"action" => unquote(action), "fields" => @all_fields})
    end
  end
end
