# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.JavaTimeSerializationTest do
  @moduledoc """
  `datetime_library: :java_time` has to produce a client that compiles and decodes.

  kotlinx-serialization ships no serializer for any `java.time` type, so a bare
  `java.time.LocalDate` field inside a `@Serializable` class is a compile error -
  SERIALIZER_NOT_FOUND - not a runtime one. The option is documented in
  `README.md`, and until #45 it could not produce a compiling client for any
  resource with a date attribute.

  The fix mirrors what `:kotlinx_datetime` already does for `Instant`: annotate the
  fields `@Contextual` and register a hand-written ISO-8601 `KSerializer` for each
  type in the `SerializersModule` of `createHttpClient()`. Annotation alone would
  trade a compile error for a decode-time throw.
  """
  # Not async: swaps :datetime_library, which is global.
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Rpc.Codegen
  alias AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic
  alias AshKotlinMultiplatform.Test.Event

  @java_time_types [
    "java.time.LocalDate",
    "java.time.LocalTime",
    "java.time.Instant",
    "java.time.ZonedDateTime",
    "java.time.LocalDateTime"
  ]

  # The serializer declarations name their own types outside any field, so exempt
  # the lines that carry them.
  @serializer_lines [
    "Iso8601Serializer",
    "PrimitiveSerialDescriptor(",
    "fun serialize(",
    "fun deserialize(",
    ".parse(",
    "DateTimeFormatter"
  ]

  defp bare_java_times(kotlin) do
    kotlin
    |> String.split("\n")
    |> Enum.reject(fn line -> Enum.any?(@serializer_lines, &String.contains?(line, &1)) end)
    |> Enum.filter(fn line ->
      Enum.any?(@java_time_types, fn type ->
        String.contains?(line, type) and not String.contains?(line, "@Contextual #{type}")
      end)
    end)
  end

  defp assert_no_bare_java_times(kotlin) do
    assert bare_java_times(kotlin) == [],
           "java.time type without @Contextual:\n" <> Enum.join(bare_java_times(kotlin), "\n")
  end

  defp put_datetime_library(library) do
    previous = Application.get_env(:ash_kotlin_multiplatform, :datetime_library)
    Application.put_env(:ash_kotlin_multiplatform, :datetime_library, library)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:ash_kotlin_multiplatform, :datetime_library)
        value -> Application.put_env(:ash_kotlin_multiplatform, :datetime_library, value)
      end
    end)
  end

  describe "with datetime_library: :java_time" do
    setup do
      put_datetime_library(:java_time)

      previous_domains = Application.get_env(:ash_kotlin_multiplatform, :ash_domains)

      Application.put_env(:ash_kotlin_multiplatform, :ash_domains, [
        AshKotlinMultiplatform.Test.Domain
      ])

      on_exit(fn ->
        case previous_domains do
          nil -> Application.delete_env(:ash_kotlin_multiplatform, :ash_domains)
          value -> Application.put_env(:ash_kotlin_multiplatform, :ash_domains, value)
        end
      end)

      :ok
    end

    test "annotates a date attribute" do
      kotlin = ResourceSchemas.generate_data_class(Event, [Event])

      assert kotlin =~ "val startsOn: @Contextual java.time.LocalDate? = null"
    end

    test "annotates the element type of a datetime list, not the list itself" do
      kotlin = ResourceSchemas.generate_data_class(Event, [Event])

      assert kotlin =~ "val reminderAts: List<@Contextual java.time.Instant>? = null"
    end

    test "declares a serializer for every java.time type it can emit" do
      kotlin = KotlinStatic.generate_http_client_factory()

      for type <- @java_time_types do
        assert kotlin =~ "KSerializer<#{type}>",
               "no KSerializer declared for #{type}"
      end
    end

    test "registers every serializer on the Json config" do
      kotlin = KotlinStatic.generate_http_client_factory()

      assert kotlin =~ "serializersModule = SerializersModule {"
      assert kotlin =~ "contextual(JavaLocalDateIso8601Serializer)"
      assert kotlin =~ "contextual(JavaLocalTimeIso8601Serializer)"
      assert kotlin =~ "contextual(JavaInstantIso8601Serializer)"
      assert kotlin =~ "contextual(JavaZonedDateTimeIso8601Serializer)"
      assert kotlin =~ "contextual(JavaLocalDateTimeIso8601Serializer)"
    end

    test "imports the serialization types the serializers name" do
      kotlin = KotlinStatic.generate_imports()

      assert kotlin =~ "import java.time.*"
      assert kotlin =~ "import kotlinx.serialization.KSerializer"
      assert kotlin =~ "import kotlinx.serialization.modules.SerializersModule"
      assert kotlin =~ "import kotlinx.serialization.modules.contextual"
    end

    test "carries no bare java.time type anywhere in the generated file" do
      {:ok, kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform, with_filters: true)

      assert_no_bare_java_times(kotlin)
    end
  end

  describe "with datetime_library: :kotlinx_datetime" do
    setup do
      put_datetime_library(:kotlinx_datetime)
      :ok
    end

    test "emits no java.time serializer" do
      kotlin = KotlinStatic.generate_http_client_factory()

      refute kotlin =~ "java.time"
    end

    test "leaves a date attribute bare, since kotlinx-datetime serializes it" do
      kotlin = ResourceSchemas.generate_data_class(Event, [Event])

      assert kotlin =~ "val startsOn: kotlinx.datetime.LocalDate? = null"
    end
  end
end
