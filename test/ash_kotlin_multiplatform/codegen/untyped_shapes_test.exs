# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.UntypedShapesTest do
  @moduledoc """
  An Ash shape with no Kotlin type reaches Kotlin as `JsonElement`, never as
  `Any`.

  `Any` compiles only under `@Contextual`, and `@Contextual` is a
  `SerializersModule` lookup that no module can satisfy: kotlinx-serialization
  has no serializer for `Any` and never will. #50 made the annotation carry the
  compile, and #51 measured what that bought — a populated untyped map still
  threw `SerializationException: Serializer for class 'Any' is not found`, while
  absent and null maps decoded fine.

  `JsonElement` needs no module, so it decodes through any `Json` a consumer
  builds, and it keeps the literal a number arrived as. See `docs/decisions.md`
  for why that beat registering an `Any` serializer.

  `Any` is still annotated on the way into a serializable field, because
  `:untyped_map_type` and `:type_mapping_overrides` let a consumer name one.
  """
  # Not async: one describe swaps :untyped_map_type, which is global.
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Rpc.Codegen
  alias AshKotlinMultiplatform.Test.{Author, Book, Event, Todo, User}

  @resources [Author, Book, Event, Todo, User]

  defp schemas do
    {data_classes, embedded_classes, enum_classes, sealed_classes} =
      ResourceSchemas.generate_all_schemas(@resources)

    Enum.join([data_classes, embedded_classes, enum_classes, sealed_classes], "\n")
  end

  defp anys(kotlin) do
    ~r/\bAny\b/
    |> Regex.scan(kotlin, return: :index)
    |> Enum.map(fn [{start, _}] ->
      kotlin
      |> String.slice(max(start - 60, 0), 120)
      |> String.trim()
    end)
  end

  describe "the generated schema types" do
    test "carry no Any at all, annotated or otherwise" do
      assert anys(schemas()) == []
    end

    test "map an untyped map attribute to JsonElement values" do
      assert schemas() =~ "val metadata: Map<String, JsonElement>? = null"
    end

    test "map a keyword attribute to JsonElement values" do
      assert schemas() =~ "val settings: Map<String, JsonElement>? = null"
    end

    test "map a tuple attribute to a list of JsonElement" do
      assert schemas() =~ "val position: List<JsonElement>? = null"
    end

    test "map an attribute whose Ash type has no Kotlin mapping to JsonElement" do
      assert schemas() =~ "val scratch: JsonElement? = null"
    end

    test "map an untyped map inside a union subclass" do
      assert schemas() =~ "val value: Map<String, JsonElement>"
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

    defp generated do
      {:ok, kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform, with_filters: true)
      kotlin
    end

    # `fields: List<Any>` and the hook context maps are the exceptions: neither
    # sits inside a `@Serializable` declaration, so neither reaches a serializer
    # through a generated class.
    test "puts Any in no serializable declaration" do
      remaining =
        generated()
        |> anys()
        |> Enum.reject(&String.contains?(&1, "fields: List<Any>"))
        |> Enum.reject(&String.contains?(&1, "Map<String, Any?>"))

      assert remaining == []
    end

    test "types the filter and page config maps as JsonElement" do
      kotlin = generated()

      assert kotlin =~ "val filter: Map<String, JsonElement>? = null"
      assert kotlin =~ "val page: Map<String, JsonElement>? = null"
    end

    test "types the error details map as JsonElement" do
      assert generated() =~ "val details: Map<String, JsonElement>? = null"
    end
  end

  describe "a configured untyped_map_type naming Any" do
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

    test "is still annotated, so a consumer who names Any still compiles" do
      assert schemas() =~ "val metadata: Map<String, @Contextual Any?>? = null"
    end
  end
end
