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

    test "maps Map type to Map<String, Any?>" do
      attr = %{type: Ash.Type.Map, constraints: [], allow_nil?: false}
      assert TypeMapper.get_kotlin_type(attr) == "Map<String, Any?>"
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

    test "handles unknown types as Any" do
      assert TypeMapper.get_kotlin_type_for_type(:unknown_type) == "Any"
    end
  end
end
