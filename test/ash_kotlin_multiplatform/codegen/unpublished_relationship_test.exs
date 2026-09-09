# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.UnpublishedRelationshipTest do
  @moduledoc """
  A relationship field may only name a type the same file declares.

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
  alias AshKotlinMultiplatform.Test.{Author, Book}

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
        ResourceSchemas.generate_all_schemas([Author, Book])

      kotlin = Enum.join([data_classes, embedded_classes, enum_classes, sealed_classes], "\n")

      refute kotlin =~ "Secret"
      assert kotlin =~ "data class Author("
      assert kotlin =~ "data class Book("
    end
  end
end
