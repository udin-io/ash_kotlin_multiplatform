# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.ResourceSchemasTest do
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Rpc.Codegen
  alias AshKotlinMultiplatform.Test.Todo

  # The whole generated file, once: the embedded-class tests read it.
  setup_all do
    {:ok, kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
    %{kotlin: kotlin}
  end

  describe "generate_data_class/2" do
    test "a union attribute names the sealed class generated for it" do
      assert ResourceSchemas.generate_data_class(Todo, [Todo]) =~
               "val content: ContentUnion? = null"
    end

    test "a one_of atom attribute names the enum class generated for it" do
      assert ResourceSchemas.generate_data_class(Todo, [Todo]) =~ "val status: Status? = null"
    end
  end

  describe "embedded resource classes in the generated Kotlin" do
    # One fixture per route to an embedded resource, measured in #84. The
    # one-level attribute walk found only `BookMeta`; the others were either
    # named and never declared (`Edition`, `UnionNote`, `SummaryOpts`) or
    # absent. They come from `manifest.types` now.
    for {class, route} <- [
          {"BookMeta", "an attribute of a published resource"},
          {"Edition", "another embedded resource"},
          {"UnionNote", "a union member"},
          {"SummaryOpts", "a generic action argument"},
          {"Summary", "a generic action return"},
          {"Cover", "a calculation"},
          {"SecretNote", "a relationship to an unpublished resource"},
          {"VaultSeal", "a private relationship"}
        ] do
      test "declares #{class}, reached through #{route}", %{kotlin: kotlin} do
        assert kotlin =~ "data class #{unquote(class)}("
      end
    end

    test "declares nothing for a type reached only through a first aggregate",
         %{kotlin: kotlin} do
      # Upstream gap, out of scope for #84: the aggregate's type is nil when the
      # manifest is built, so `PrivateMeta` is not in `manifest.types`. Nothing
      # in the generated file names it either. If this starts failing, Ash
      # fixed the gap; update `docs/risks.md`.
      refute kotlin =~ "PrivateMeta"
    end
  end

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
