# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.Helpers.PayloadBuilderTest do
  @moduledoc """
  #62: `config.fields` holds a nested selection Kotlin cannot statically type
  narrower than `List<Any>`, and asking kotlinx-serialization to
  `encodeToJsonElement` a value it only knows as `Any` throws
  `SerializationException: Serializer for class 'Any' is not found` at
  runtime, past a clean compile. This pins the fix at the Elixir level, so a
  later edit can't quietly reintroduce the old call — even though the Kotlin
  gate (`gradle run`, `Roundtrip.kt`) would also catch it.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Codegen.Helpers.{ConfigBuilder, PayloadBuilder}
  alias AshKotlinMultiplatform.Test.Event

  defp payload_for(action_name, rpc_action_name) do
    action = Ash.Resource.Info.action(Event, action_name)
    context = ConfigBuilder.get_action_context(Event, action, %{})
    PayloadBuilder.build_payload_code(rpc_action_name, context, include_fields: true)
  end

  describe "build_payload_code/3 with include_fields: true" do
    test "never asks kotlinx to encode a fields element typed Any" do
      refute payload_for(:read, :list_events) =~ "encodeToJsonElement(field)"
    end

    test "walks a fields element by hand instead" do
      assert payload_for(:read, :list_events) =~ "add(ashFieldToJsonElement(field))"
    end

    test "embeds the ashFieldToJsonElement local function" do
      assert payload_for(:read, :list_events) =~
               "fun ashFieldToJsonElement(value: Any?): JsonElement"
    end
  end
end
