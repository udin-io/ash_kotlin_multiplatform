# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.TypedQueriesTest do
  @moduledoc """
  `TypedQueries` has no dedicated test file before #63 — `typed_query` codegen
  was previously exercised only indirectly, through the manifest tests.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.TypedQueries
  alias AshKotlinMultiplatform.Rpc.TypedQuery
  alias AshKotlinMultiplatform.Test.{Author, Book, ScopedDomain}

  describe "generate_typed_query_type_and_const/4" do
    test "honors kotlin_fields_const_name for the fields object name" do
      [config] = AshKotlinMultiplatform.Rpc.Info.kotlin_rpc(ScopedDomain)
      [typed_query] = config.typed_queries
      action = Ash.Resource.Info.action(config.resource, typed_query.action)

      kotlin =
        TypedQueries.generate_typed_query_type_and_const(config.resource, action, typed_query, [
          config.resource
        ])

      assert kotlin =~ "object BOOK_TITLES_FIELDS {"
    end

    test "an attribute generates the same field whether the typed_query names it by atom or string" do
      action = Ash.Resource.Info.action(Book, :read)

      atom_query = %TypedQuery{
        name: :book_titles,
        fields: [:id, :title],
        resource: Book,
        action: :read
      }

      string_query = %TypedQuery{
        name: :book_titles,
        fields: ["id", "title"],
        resource: Book,
        action: :read
      }

      atom_kotlin =
        TypedQueries.generate_typed_query_type_and_const(Book, action, atom_query, [Book])

      string_kotlin =
        TypedQueries.generate_typed_query_type_and_const(Book, action, string_query, [Book])

      assert atom_kotlin == string_kotlin
      assert atom_kotlin =~ "val id: String"
      assert atom_kotlin =~ "val title: String"
    end

    test "scoped_manifest.ex's book_titles typed query (string fields) emits real members, not blank ones" do
      [config] = AshKotlinMultiplatform.Rpc.Info.kotlin_rpc(ScopedDomain)
      [typed_query] = config.typed_queries
      action = Ash.Resource.Info.action(config.resource, typed_query.action)

      kotlin =
        TypedQueries.generate_typed_query_type_and_const(config.resource, action, typed_query, [
          config.resource
        ])

      assert kotlin =~ "val id: String"
      assert kotlin =~ "val title: String"
      refute kotlin =~ "data class BookTitlesResult(\n    ,"
    end

    test "a public relationship with nested public fields generates a nested data class (happy path guard)" do
      action = Ash.Resource.Info.action(Book, :read)

      typed_query = %TypedQuery{
        name: :book_with_author,
        fields: [:title, author: [:id, :name]],
        resource: Book,
        action: :read
      }

      kotlin =
        TypedQueries.generate_typed_query_type_and_const(Book, action, typed_query, [
          Book,
          Author
        ])

      assert kotlin =~ "val author: BookWithAuthorResultAuthorResult?"
      assert kotlin =~ "data class BookWithAuthorResultAuthorResult("
      assert kotlin =~ "val id: String"
      assert kotlin =~ "val name: String"
    end

    test "an unresolvable field falls back to Any? rather than crashing (defense in depth; VerifyTypedQueryFields is the real gate)" do
      action = Ash.Resource.Info.action(Book, :read)

      typed_query = %TypedQuery{
        name: :book_titles,
        fields: [:totally_not_a_field],
        resource: Book,
        action: :read
      }

      kotlin = TypedQueries.generate_typed_query_type_and_const(Book, action, typed_query, [Book])

      assert kotlin =~ "val totallyNotAField: Any?"
    end
  end
end
