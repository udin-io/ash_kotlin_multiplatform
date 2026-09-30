# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.UnpublishedResourceTest do
  @moduledoc """
  Generated Kotlin may only name a type the same file declares.

  `Author.secrets` is a public `has_many` to `AshKotlinMultiplatform.Test.Secret`,
  a resource the Kotlin DSL never publishes. The generator used to emit
  `val secrets: List<Secret>?` against a `Secret` class that exists nowhere, so
  every generated file failed to compile with "Unresolved reference 'Secret'".

  The client side now agrees with the server side: `AshKotlinMultiplatform.Rpc.Runner`
  hands `FieldSelector` an `is_interop_resource?` gate so a nested request into
  `Author.secrets` returns `unknown_field`. A field the server refuses to answer
  is a field the client has no use for.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Rpc.Codegen
  alias AshKotlinMultiplatform.Test.{Author, Book}

  # One full generation pass, shared: the tests below read what a consumer's
  # file holds, and the pass takes most of a second.
  setup_all do
    {:ok, kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
    %{kotlin: kotlin}
  end

  defp author_class(emitted) do
    ResourceSchemas.generate_data_class(Author, emitted)
  end

  describe "a relationship to a resource with no generated type" do
    test "is omitted from the data class" do
      kotlin = author_class([Author, Book])

      refute kotlin =~ "secrets"
      refute kotlin =~ "Secret"
    end

    test "is omitted even when the destination is the only thing missing" do
      kotlin = author_class([Author])

      refute kotlin =~ "Secret"
      refute kotlin =~ "List<Book>"
    end
  end

  describe "a relationship to a published resource" do
    test "is kept" do
      assert author_class([Author, Book]) =~ "val books: List<Book>? = null"
    end

    test "is kept in the belongs_to direction" do
      assert ResourceSchemas.generate_data_class(Book, [Author, Book]) =~
               "val author: Author? = null"
    end
  end

  describe "the whole schema pass" do
    test "names no type it does not declare" do
      {data_classes, embedded_classes, enum_classes, sealed_classes} =
        ResourceSchemas.generate_all_schemas([Author, Book], Manifest.embedded_resources())

      kotlin = Enum.join([data_classes, embedded_classes, enum_classes, sealed_classes], "\n")

      # A word boundary, because `SecretNote` is declared: it is embedded in
      # `Secret` and reached through the manifest (#84).
      refute kotlin =~ ~r/\bSecret\b/
      assert kotlin =~ "data class Author("
      assert kotlin =~ "data class Book("
    end
  end

  describe "a value typed as an unpublished resource" do
    test "is a JsonElement attribute on the data class", %{kotlin: kotlin} do
      assert kotlin =~ "val secretRef: JsonElement? = null"
    end

    # #33 (owner): named after its resource, `BookExtraUnion`, not
    # `ExtraUnion`.
    test "is a JsonElement union member", %{kotlin: kotlin} do
      assert kotlin =~
               ~r/data class Hidden\(\s*val value: JsonElement\s*\) : BookExtraUnion\(\)/
    end

    test "is a JsonElement action argument", %{kotlin: kotlin} do
      assert kotlin =~ ~r/data class RevealSecretInput\(\s*val secret: JsonElement\? = null/
    end

    test "is a JsonElement generic action return", %{kotlin: kotlin} do
      assert kotlin =~
               ~r/suspend fun revealSecret\([^)]*\): RpcResult<JsonElement>/
    end

    # A word boundary, because `SecretNote`, `RevealSecretInput` and
    # `revealSecret` are all declared.
    test "is never named as a class anywhere in the file", %{kotlin: kotlin} do
      refute kotlin =~ ~r/\bSecret\b/
    end
  end
end
