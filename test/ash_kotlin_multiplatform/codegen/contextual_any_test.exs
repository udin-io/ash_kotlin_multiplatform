# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.ContextualAnyTest do
  @moduledoc """
  kotlinx-serialization has no serializer for `Any`, so a bare `Any` anywhere
  inside a `@Serializable` declaration is a compile error, not a runtime one:
  "Serializer has not been found for type 'Any'". Every schema type this library
  emits is `@Serializable`, so none of them may carry one.
  """
  # Not async: one describe swaps :untyped_map_type, which is global.
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Test.{Author, Book, Event, Todo, User}

  @resources [Author, Book, Event, Todo, User]

  defp schemas do
    {data_classes, embedded_classes, enum_classes, sealed_classes} =
      ResourceSchemas.generate_all_schemas(@resources)

    Enum.join([data_classes, embedded_classes, enum_classes, sealed_classes], "\n")
  end

  defp bare_anys(kotlin) do
    ~r/(?<!@Contextual )\bAny\b/
    |> Regex.scan(kotlin, return: :index)
    |> Enum.map(fn [{start, _}] ->
      kotlin
      |> String.slice(max(start - 60, 0), 120)
      |> String.trim()
    end)
  end

  describe "the generated schema types" do
    test "carry no bare Any" do
      assert bare_anys(schemas()) == []
    end

    test "annotate an untyped map attribute" do
      assert schemas() =~ "val metadata: Map<String, @Contextual Any?>? = null"
    end

    test "annotate a keyword attribute" do
      assert schemas() =~ "val settings: Map<String, @Contextual Any?>? = null"
    end

    test "annotate a tuple attribute" do
      assert schemas() =~ "val position: List<@Contextual Any?>? = null"
    end

    test "annotate an attribute whose Ash type has no Kotlin mapping" do
      assert schemas() =~ "val scratch: @Contextual Any? = null"
    end

    test "annotate an untyped map inside a union subclass" do
      assert schemas() =~ "val value: Map<String, @Contextual Any?>"
    end
  end

  describe "a configured untyped_map_type without the annotation" do
    setup do
      previous = Application.get_env(:ash_kotlin_multiplatform, :untyped_map_type)
      Application.put_env(:ash_kotlin_multiplatform, :untyped_map_type, "Map<String, Any?>")

      on_exit(fn ->
        case previous do
          nil -> Application.delete_env(:ash_kotlin_multiplatform, :untyped_map_type)
          value -> Application.put_env(:ash_kotlin_multiplatform, :untyped_map_type, value)
        end
      end)

      :ok
    end

    test "is still annotated on the way into a serializable field" do
      assert bare_anys(schemas()) == []
    end
  end
end
