# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.InstantSerializationTest do
  @moduledoc """
  Every `kotlinx.datetime.Instant` the generator emits must be annotated
  `@Contextual`, in every `@Serializable` class and in type position.

  kotlinx-datetime 0.6 shipped a default serializer for `Instant`; 0.7 dropped it
  when it deprecated the class in favour of `kotlin.time.Instant`. A bare field
  therefore fails to compile on 0.7, and the generator cannot know which version a
  consumer pinned. These tests exist because the first pass at that fix covered
  only resource data classes and left the input, filter, metadata and typed-query
  emitters broken.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Codegen.FilterTypes
  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Codegen.TypedQueries
  alias AshKotlinMultiplatform.Rpc.Codegen
  alias AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.InputTypes
  alias AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.MetadataTypes
  alias AshKotlinMultiplatform.Test.Event

  # The serializer's own declaration names Instant outside any field, so exempt it.
  @serializer_lines [
    "object InstantIso8601Serializer",
    "PrimitiveSerialDescriptor(",
    "fun serialize(",
    "fun deserialize(",
    "Instant.parse("
  ]

  defp bare_instants(kotlin) do
    kotlin
    |> String.split("\n")
    |> Enum.reject(fn line -> Enum.any?(@serializer_lines, &String.contains?(line, &1)) end)
    |> Enum.filter(fn line ->
      String.contains?(line, "kotlinx.datetime.Instant") and
        not String.contains?(line, "@Contextual kotlinx.datetime.Instant")
    end)
  end

  defp assert_no_bare_instants(kotlin) do
    assert bare_instants(kotlin) == [],
           "Instant without @Contextual:\n" <> Enum.join(bare_instants(kotlin), "\n")
  end

  describe "resource data classes" do
    test "annotates Instant attributes" do
      kotlin = ResourceSchemas.generate_data_class(Event)

      assert kotlin =~ "val occurredAt: @Contextual kotlinx.datetime.Instant? = null"
      assert_no_bare_instants(kotlin)
    end

    test "annotates the element type of an Instant list, not the list itself" do
      kotlin = ResourceSchemas.generate_data_class(Event)

      assert kotlin =~ "val reminderAts: List<@Contextual kotlinx.datetime.Instant>? = null"
    end

    test "leaves types with a built-in serializer bare" do
      kotlin = ResourceSchemas.generate_data_class(Event)

      assert kotlin =~ "val startsOn: kotlinx.datetime.LocalDate? = null"
    end
  end

  describe "action input types" do
    test "annotates Instant attributes accepted by the action" do
      kotlin = InputTypes.generate_input_type(Event, %{name: :create_event, action: :create})

      assert kotlin =~ "val occurredAt: @Contextual kotlinx.datetime.Instant? = null"
      assert kotlin =~ "val reminderAts: List<@Contextual kotlinx.datetime.Instant>? = null"
      assert_no_bare_instants(kotlin)
    end
  end

  describe "base filter types" do
    test "annotates every InstantFilter field" do
      assert_no_bare_instants(FilterTypes.generate_base_filter_types())
    end
  end

  describe "action metadata types" do
    test "annotates Instant metadata fields" do
      action = %{
        metadata: [
          %{name: :confirmed_at, type: Ash.Type.UtcDatetime, constraints: [], allow_nil?: true}
        ]
      }

      kotlin = MetadataTypes.generate_action_metadata_type(action, %{}, :confirm_user)

      assert kotlin =~ "val confirmedAt: @Contextual kotlinx.datetime.Instant? = null"
      assert_no_bare_instants(kotlin)
    end
  end

  describe "typed query result types" do
    test "annotates Instant fields" do
      action = Ash.Resource.Info.action(Event, :read)
      typed_query = %{name: :recent_events, fields: [:id, :occurred_at]}

      kotlin =
        TypedQueries.generate_typed_query_type_and_const(Event, action, typed_query, [Event])

      assert kotlin =~ "@Contextual kotlinx.datetime.Instant"
      assert_no_bare_instants(kotlin)
    end
  end

  describe "the whole generated file" do
    setup do
      previous = Application.get_env(:ash_kotlin_multiplatform, :ash_domains)

      Application.put_env(:ash_kotlin_multiplatform, :ash_domains, [
        AshKotlinMultiplatform.Test.Domain
      ])

      on_exit(fn ->
        case previous do
          nil -> Application.delete_env(:ash_kotlin_multiplatform, :ash_domains)
          value -> Application.put_env(:ash_kotlin_multiplatform, :ash_domains, value)
        end
      end)

      :ok
    end

    test "carries no bare Instant anywhere" do
      {:ok, kotlin} =
        Codegen.generate_kotlin_code(:ash_kotlin_multiplatform, with_filters: true)

      assert_no_bare_instants(kotlin)
    end

    test "registers the Instant serializer on the Json config" do
      {:ok, kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)

      assert kotlin =~ "object InstantIso8601Serializer : KSerializer<kotlinx.datetime.Instant>"

      assert kotlin =~
               "serializersModule = SerializersModule { contextual(InstantIso8601Serializer) }"
    end
  end
end
