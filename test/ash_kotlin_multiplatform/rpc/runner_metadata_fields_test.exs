# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerMetadataFieldsTest do
  @moduledoc """
  The generated Kotlin client sends `metadataFields`; the server must honor it.

  The invariant under test: the client can only narrow. Whatever it asks for is
  intersected with the fields the DSL exposes, so a name the DSL withholds
  yields nothing and no error that would reveal the field exists.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  # `register_event` exposes both metadata fields; `register_event_narrow`
  # exposes only `registered_at`. Both run the same `:register` action, which
  # sets both fields to fixed values.
  defp register(action, params \\ %{}) do
    Runner.run_action(
      :ash_kotlin_multiplatform,
      Map.merge(%{"action" => action, "input" => %{"name" => "Launch"}}, params)
    )
  end

  defp metadata(response) do
    assert %{"success" => true, "data" => data} = response
    Map.get(data, "metadata", %{})
  end

  test "a subset request returns exactly that subset" do
    metadata = metadata(register("register_event", %{"metadataFields" => ["registeredAt"]}))

    assert metadata == %{"registeredAt" => ~U[2026-01-01 00:00:00Z]}
  end

  test "snake_case names work as well as the camelCase the client sends" do
    metadata = metadata(register("register_event", %{"metadataFields" => ["registered_at"]}))

    assert metadata == %{"registeredAt" => ~U[2026-01-01 00:00:00Z]}
  end

  test "a field the DSL does not expose is withheld and the request still succeeds" do
    response =
      register("register_event_narrow", %{
        "metadataFields" => ["registeredAt", "confirmationCode"]
      })

    assert %{"success" => true} = response
    assert metadata(response) == %{"registeredAt" => ~U[2026-01-01 00:00:00Z]}
  end

  test "an attribute name is not a way to smuggle out extra metadata" do
    response = register("register_event", %{"metadataFields" => ["id"]})

    assert %{"success" => true} = response
    assert metadata(response) == %{}
  end

  test "an empty list returns no metadata" do
    response = register("register_event", %{"metadataFields" => []})

    assert %{"success" => true} = response
    assert metadata(response) == %{}
  end

  test "an absent param returns everything the DSL exposes" do
    assert metadata(register("register_event")) == %{
             "registeredAt" => ~U[2026-01-01 00:00:00Z],
             "confirmationCode" => "AKM-1"
           }
  end

  test "a nil param returns everything the DSL exposes" do
    assert metadata(register("register_event", %{"metadataFields" => nil})) == %{
             "registeredAt" => ~U[2026-01-01 00:00:00Z],
             "confirmationCode" => "AKM-1"
           }
  end

  test "a name that is not an existing atom is dropped rather than crashing" do
    response =
      register("register_event", %{
        "metadataFields" => ["registeredAt", "no_such_metadata_field_anywhere"]
      })

    assert %{"success" => true} = response
    assert metadata(response) == %{"registeredAt" => ~U[2026-01-01 00:00:00Z]}
  end

  test "a garbage name does not grow the atom table" do
    register("register_event", %{"metadataFields" => ["definitely_not_an_atom_yet_9f3a"]})

    assert_raise ArgumentError, fn ->
      String.to_existing_atom("definitely_not_an_atom_yet_9f3a")
    end
  end
end
