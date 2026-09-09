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

    test "maps Map type to a contextual untyped map" do
      attr = %{type: Ash.Type.Map, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "Map<String, @Contextual Any?>"
    end

    test "maps Keyword type to a contextual untyped map" do
      attr = %{type: Ash.Type.Keyword, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "Map<String, @Contextual Any?>"
    end

    test "maps Tuple type to a list of contextual values" do
      attr = %{type: Ash.Type.Tuple, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "List<@Contextual Any?>"
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

    test "handles unknown types as a contextual Any" do
      assert TypeMapper.get_kotlin_type_for_type(:unknown_type) == "@Contextual Any"
    end

    test "handles an Ash type with no mapping as a contextual Any" do
      assert TypeMapper.get_kotlin_type_for_type(Ash.Type.Term) == "@Contextual Any"
    end

    test "handles a union with no owning attribute as a contextual Any" do
      constraints = [types: [text: [type: Ash.Type.String]]]
      assert TypeMapper.get_kotlin_type_for_type(Ash.Type.Union, constraints) == "@Contextual Any"
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
