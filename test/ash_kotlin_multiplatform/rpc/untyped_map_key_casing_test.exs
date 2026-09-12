# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.UntypedMapKeyCasingTest do
  @moduledoc """
  An untyped map's keys are data, and data is sent back as it was stored.

  This is a deliberate wire change from #71, and the one behaviour change the
  vector fix carries with it. `Pipeline.format_output/1` renamed every key it
  walked, at every depth, because it could not tell a field name from a map key
  — so a `:map` attribute holding `%{"created_by" => "ada"}` reached the client
  as `createdBy`. Stage 4 is type-aware now, and `Ash.Type.Map` with no `fields`
  constraint has no field names to rename, so the keys survive the round trip.

  It is the correct answer and not merely a consequence. A typed map declares
  its fields, so those names are part of the schema and are still formatted —
  `Todo.settings` below proves that half. An untyped map declares nothing: its
  keys came from the caller, the Kotlin side decodes it as the untyped-map type
  whatever they say, and renaming them meant a value written as `created_by`
  could never be read back under the name it was written with.

  No test covered this before, which is why it went unnoticed: every key in the
  round-trip fixture's `populated_untyped_map` entry is a single word, and a
  single word is identical in both casings.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  defp create_todo(input) do
    assert %{"success" => true, "data" => data} =
             Runner.run_action(:ash_kotlin_multiplatform, %{
               "action" => "create_todo",
               "input" => Map.put(input, "title", "Casing")
             })

    data
  end

  describe "an untyped :map attribute" do
    test "keeps a snake_case key exactly as it was written" do
      data = create_todo(%{"metadata" => %{"created_by" => "ada", "retry_count" => 3}})

      assert data["metadata"] == %{"created_by" => "ada", "retry_count" => 3}
    end

    # Not the behaviour anyone would design, and not changed here. `Runner`
    # parses `input` before it knows any field's type, so
    # `convert_keys_to_atoms/2` snake-cases every nested key it walks — data
    # keys inside an untyped map included. Output no longer renames, so a key
    # sent as `createdBy` is stored and returned as `created_by`.
    #
    # Left alone deliberately: fixing it means resolving input keys by type,
    # and the parser cannot mint atoms for unknown names without reopening the
    # atom-table exhaustion #18 closed. Filed rather than fixed under #71; this
    # test exists so the next person finds the asymmetry described instead of
    # rediscovering it.
    test "a camelCase key is still snake_cased on the way IN, which output no longer undoes" do
      data = create_todo(%{"metadata" => %{"createdBy" => "ada"}})

      assert data["metadata"] == %{"created_by" => "ada"}
    end

    test "keeps nested keys too" do
      data = create_todo(%{"metadata" => %{"outer_key" => %{"inner_key" => 1}}})

      assert data["metadata"] == %{"outer_key" => %{"inner_key" => 1}}
    end

    test "the keys survive JSON encoding" do
      json =
        %{"metadata" => %{"created_by" => "ada"}}
        |> create_todo()
        |> Phoenix.json_library().encode!()

      assert json =~ ~s("created_by":"ada")
      refute json =~ "createdBy"
    end
  end

  describe "a typed map still has its declared field names formatted" do
    test "a declared snake_case field name is camelCased on the way out" do
      data = create_todo(%{"settings" => %{"notifyByEmail" => true}})

      assert data["settings"] == %{"notify" => nil, "notifyByEmail" => true}
      refute Map.has_key?(data["settings"], "notify_by_email")
    end
  end
end
