# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerUnionReadSelectionTest do
  @moduledoc """
  A read that selects a union attribute's nested member fields gets those
  fields, not `null`.

  This is the other half of ash_introspection #84, fixed in 0.5.1:
  `FieldSelector` keyed a nested union member entry by its wire name while
  `ResultProcessor` matches a member against the atom `%Ash.Union{type:}`
  carries, so `Book.extra` came back `null` from a single record and dropped
  from a list.

  The fix is upstream, so this test guards the floor rather than any code in
  this repository. A downgrade to 0.5.0 fails it.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Rpc.Runner
  alias AshKotlinMultiplatform.Test.Book
  alias AshKotlinMultiplatform.Test.UnionNote

  setup do
    Ash.create!(Book, %{
      title: "Kindred",
      extra: %Ash.Union{type: :note, value: %UnionNote{label: "Read me"}}
    })

    :ok
  end

  test "a read selecting a union member's nested fields returns them" do
    assert %{"success" => true, "data" => data} =
             Runner.run_action(:ash_kotlin_multiplatform, %{
               "action" => "list_books",
               "fields" => ["title", %{"extra" => [%{"note" => ["label"]}]}]
             })

    assert Enum.find(data, &(&1["title"] == "Kindred")) ==
             %{"title" => "Kindred", "extra" => %{"note" => %{"label" => "Read me"}}}
  end
end
