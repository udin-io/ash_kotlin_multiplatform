# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.TypeMapperTest do
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.TypeMapper

  describe "get_kotlin_type/2" do
    test "maps String type to String" do
      attr = %{type: Ash.Type.String, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "String"
    end

    test "maps nullable String type to String?" do
      attr = %{type: Ash.Type.String, constraints: [], allow_nil?: true}
      assert TypeMapper.get_kotlin_type(attr) == "String?"
    end

    test "maps Integer type to Int" do
      attr = %{type: Ash.Type.Integer, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "Int"
    end

    test "maps Float type to Double" do
      attr = %{type: Ash.Type.Float, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "Double"
    end

    test "maps Boolean type to Boolean" do
      attr = %{type: Ash.Type.Boolean, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "Boolean"
    end

    test "maps UUID type to String" do
      attr = %{type: Ash.Type.UUID, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "String"
    end

    test "maps Date type to kotlinx.datetime.LocalDate" do
      attr = %{type: Ash.Type.Date, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "kotlinx.datetime.LocalDate"
    end

    test "maps DateTime type to kotlinx.datetime.Instant" do
      attr = %{type: Ash.Type.DateTime, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "kotlinx.datetime.Instant"
    end

    test "maps UtcDatetime type to kotlinx.datetime.Instant" do
      attr = %{type: Ash.Type.UtcDatetime, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "kotlinx.datetime.Instant"
    end

    test "maps array types to List<T>" do
      attr = %{type: {:array, Ash.Type.String}, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "List<String>"
    end

    test "maps nullable array types to List<T>?" do
      attr = %{type: {:array, Ash.Type.String}, constraints: [], allow_nil?: true}
      assert TypeMapper.get_kotlin_type(attr) == "List<String>?"
    end

    test "maps Map type to an untyped map of JsonElement" do
      attr = %{type: Ash.Type.Map, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "Map<String, JsonElement>"
    end

    test "maps Keyword type to an untyped map of JsonElement" do
      attr = %{type: Ash.Type.Keyword, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "Map<String, JsonElement>"
    end

    test "maps Tuple type to a list of JsonElement" do
      attr = %{type: Ash.Type.Tuple, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "List<JsonElement>"
    end

    test "maps Decimal type to String" do
      attr = %{type: Ash.Type.Decimal, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "String"
    end
  end

  describe "get_kotlin_type_for_type/2" do
    test "maps primitive types correctly" do
      assert TypeMapper.get_kotlin_type_for_type(Ash.Type.String) == "String"
      assert TypeMapper.get_kotlin_type_for_type(Ash.Type.Integer) == "Int"
      assert TypeMapper.get_kotlin_type_for_type(Ash.Type.Float) == "Double"
      assert TypeMapper.get_kotlin_type_for_type(Ash.Type.Boolean) == "Boolean"
    end

    test "handles array types" do
      assert TypeMapper.get_kotlin_type_for_type({:array, Ash.Type.String}) == "List<String>"
      assert TypeMapper.get_kotlin_type_for_type({:array, Ash.Type.Integer}) == "List<Int>"
    end

    test "handles unknown types as JsonElement" do
      assert TypeMapper.get_kotlin_type_for_type(:unknown_type) == "JsonElement"
    end

    test "handles an Ash type with no mapping as JsonElement" do
      assert TypeMapper.get_kotlin_type_for_type(Ash.Type.Term) == "JsonElement"
    end

    test "handles a union with no owning attribute as JsonElement" do
      constraints = [types: [text: [type: Ash.Type.String]]]
      assert TypeMapper.get_kotlin_type_for_type(Ash.Type.Union, constraints) == "JsonElement"
    end
  end

  # #30. Each of these reached the unknown-type fallback, so the field arrived in
  # a generated client as an opaque `JsonElement` the caller unpacked by hand.
  describe "types that fell through to the unknown-type fallback" do
    test "maps Ash.Type.Vector to a list of doubles" do
      attr = %{type: Ash.Type.Vector, constraints: [dimensions: 3], allow_nil?: true}
      assert TypeMapper.get_kotlin_type(attr) == "List<Double>?"
    end

    test "maps an array of vectors" do
      assert TypeMapper.get_kotlin_type_for_type({:array, Ash.Type.Vector}) ==
               "List<List<Double>>"
    end

    # The three below name modules this library does not depend on. Passing the
    # bare module atom is exactly what the generator does with a type it cannot
    # resolve, so it exercises the clauses without adding the packages.
    test "maps AshMoney.Types.Money to the shared AshMoney class" do
      assert TypeMapper.get_kotlin_type_for_type(AshMoney.Types.Money) == "AshMoney"
    end

    test "maps AshPostgres.Ltree to segment strings under both escape? settings" do
      assert TypeMapper.get_kotlin_type_for_type(AshPostgres.Ltree) == "List<String>"

      assert TypeMapper.get_kotlin_type_for_type(AshPostgres.Ltree, escape?: true) ==
               "List<String>"
    end

    test "maps AshDoubleEntry.ULID to String" do
      assert TypeMapper.get_kotlin_type_for_type(AshDoubleEntry.ULID) == "String"
    end
  end

  describe "is_enum_type?/2" do
    test "is true for an atom constrained to a list of values" do
      assert TypeMapper.is_enum_type?(Ash.Type.Atom, one_of: [:a, :b])
    end

    test "is false for an unconstrained atom" do
      refute TypeMapper.is_enum_type?(Ash.Type.Atom, [])
    end

    # ResourceSchemas.collect_types/1 skips a nil :one_of, so the field must not
    # name an enum class for one either — the class would never be generated.
    test "is false when one_of is present but nil" do
      refute TypeMapper.is_enum_type?(Ash.Type.Atom, one_of: nil)
    end

    test "is false for a non-atom type" do
      refute TypeMapper.is_enum_type?(Ash.Type.String, one_of: [:a, :b])
    end
  end

  describe "annotate_contextual_types/1" do
    test "annotates a bare Instant in type position" do
      assert TypeMapper.annotate_contextual_types("kotlinx.datetime.Instant") ==
               "@Contextual kotlinx.datetime.Instant"
    end

    test "annotates a nullable Instant" do
      assert TypeMapper.annotate_contextual_types("kotlinx.datetime.Instant?") ==
               "@Contextual kotlinx.datetime.Instant?"
    end

    test "annotates the element type of a list, not the list" do
      assert TypeMapper.annotate_contextual_types("List<kotlinx.datetime.Instant>?") ==
               "List<@Contextual kotlinx.datetime.Instant>?"
    end

    test "annotates every occurrence in a nested type" do
      assert TypeMapper.annotate_contextual_types(
               "Map<kotlinx.datetime.Instant, List<kotlinx.datetime.Instant>>"
             ) ==
               "Map<@Contextual kotlinx.datetime.Instant, List<@Contextual kotlinx.datetime.Instant>>"
    end

    test "leaves types with a built-in serializer alone" do
      assert TypeMapper.annotate_contextual_types("String?") == "String?"

      assert TypeMapper.annotate_contextual_types("kotlinx.datetime.LocalDate") ==
               "kotlinx.datetime.LocalDate"

      assert TypeMapper.annotate_contextual_types("kotlinx.datetime.LocalDateTime") ==
               "kotlinx.datetime.LocalDateTime"
    end

    test "annotates a bare Any" do
      assert TypeMapper.annotate_contextual_types("Any?") == "@Contextual Any?"
    end

    test "annotates the value type of a configured untyped map" do
      assert TypeMapper.annotate_contextual_types("Map<String, Any?>") ==
               "Map<String, @Contextual Any?>"
    end

    test "annotates the element type of a list of Any" do
      assert TypeMapper.annotate_contextual_types("List<Any?>?") == "List<@Contextual Any?>?"
    end

    test "leaves a type whose name merely starts with Any alone" do
      assert TypeMapper.annotate_contextual_types("AnyOf?") == "AnyOf?"
      assert TypeMapper.annotate_contextual_types("List<Anything>") == "List<Anything>"
    end

    test "is idempotent for Any" do
      once = TypeMapper.annotate_contextual_types("Map<String, Any?>")
      assert TypeMapper.annotate_contextual_types(once) == once
    end

    test "leaves java.time.Instant alone" do
      assert TypeMapper.annotate_contextual_types("java.time.Instant?") == "java.time.Instant?"
    end

    test "is idempotent" do
      once = TypeMapper.annotate_contextual_types("kotlinx.datetime.Instant?")
      assert TypeMapper.annotate_contextual_types(once) == once
    end
  end
end
