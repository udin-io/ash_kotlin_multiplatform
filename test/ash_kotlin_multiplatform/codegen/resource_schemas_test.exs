# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.ResourceSchemasTest do
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas

  describe "generate_enum_class/1" do
    test "generates enum class with SerialName annotations" do
      enum_spec = {"Status", [:pending, :in_progress, :completed]}
      result = ResourceSchemas.generate_enum_class(enum_spec)

      assert result =~ "@Serializable"
      assert result =~ "enum class Status {"
      assert result =~ "@SerialName(\"pending\") PENDING"
      assert result =~ "@SerialName(\"in_progress\") IN_PROGRESS"
      assert result =~ "@SerialName(\"completed\") COMPLETED"
    end

    test "handles enum values with dashes" do
      enum_spec = {"Priority", [:"low-priority", :"high-priority"]}
      result = ResourceSchemas.generate_enum_class(enum_spec)

      assert result =~ "@SerialName(\"low-priority\") LOW_PRIORITY"
      assert result =~ "@SerialName(\"high-priority\") HIGH_PRIORITY"
    end
  end

  describe "generate_sealed_class/1" do
    test "generates sealed class for union types" do
      union_spec =
        {"ContentUnion",
         [
           text: [type: Ash.Type.String, constraints: []],
           number: [type: Ash.Type.Integer, constraints: []]
         ]}

      result = ResourceSchemas.generate_sealed_class(union_spec)

      assert result =~ "@Serializable"
      assert result =~ "sealed class ContentUnion {"
      assert result =~ "data class Text"
      assert result =~ "data class Number"
      assert result =~ ": ContentUnion()"
    end
  end
end
