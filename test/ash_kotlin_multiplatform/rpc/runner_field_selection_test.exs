# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerFieldSelectionTest do
  @moduledoc """
  Field selection through `Runner.run_action/3`, the only entry point a client has.

  Issue #19: the runner hand-rolled selection and only understood a flat list of
  strings, so the nested map this library's own codegen emits
  (`mapOf("author" to listOf("id", "name"))`, `typed_queries.ex:318`) raised a
  `FunctionClauseError` and the generated client got a 500 from the generated
  server on its documented happy path. It also silently dropped every name that
  was not a public attribute or relationship, which made calculations and
  aggregates unreachable and turned a typo into partial data with no error.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  defp run(params) do
    Runner.run_action(:ash_kotlin_multiplatform, params)
  end

  defp create_author(name, email) do
    assert %{"success" => true, "data" => author} =
             run(%{
               "action" => "create_author",
               "input" => %{"name" => name, "email" => email},
               "fields" => ["id"]
             })

    author["id"]
  end

  defp create_book(title, author_id) do
    assert %{"success" => true} =
             run(%{
               "action" => "create_book",
               "input" => %{"title" => title, "authorId" => author_id},
               "fields" => ["id"]
             })
  end

  defp errors(response) do
    assert %{"success" => false, "errors" => errors} = response
    errors
  end

  describe "nested field selection" do
    test "a nested map returns the nested data instead of a 500" do
      author_id = create_author("Ursula Le Guin", "ursula@example.com")
      create_book("A Wizard of Earthsea", author_id)

      response =
        run(%{
          "action" => "list_authors",
          "fields" => ["id", "name", %{"books" => ["title"]}]
        })

      assert %{"success" => true, "data" => [author]} = response
      assert author["name"] == "Ursula Le Guin"
      assert author["books"] == [%{"title" => "A Wizard of Earthsea"}]
    end

    test "the nested map narrows the nested resource too" do
      author_id = create_author("Octavia Butler", "octavia@example.com")
      create_book("Kindred", author_id)

      assert %{"success" => true, "data" => [author]} =
               run(%{
                 "action" => "list_authors",
                 "fields" => [%{"books" => ["title"]}]
               })

      assert [book] = author["books"]
      refute Map.has_key?(book, "id")
    end

    test "a relationship asked for without nested fields is an error, not a crash" do
      create_author("Ted Chiang", "ted@example.com")

      assert [error] = errors(run(%{"action" => "list_authors", "fields" => ["books"]}))
      assert error["type"] == "requires_field_selection"
    end

    test "a relationship into a resource the DSL never published is refused" do
      create_author("Jorge Luis Borges", "jorge@example.com")

      assert [error] =
               errors(
                 run(%{
                   "action" => "list_authors",
                   "fields" => [%{"secrets" => ["body"]}]
                 })
               )

      assert error["type"] == "unknown_field"
    end
  end

  describe "non-attribute fields" do
    test "a calculation is reachable" do
      create_author("N. K. Jemisin", "nk@example.com")

      assert %{"success" => true, "data" => [author]} =
               run(%{"action" => "list_authors", "fields" => ["displayName"]})

      assert author["displayName"] == "N. K. Jemisin <nk@example.com>"
    end

    test "an aggregate is reachable" do
      author_id = create_author("Ann Leckie", "ann@example.com")
      create_book("Ancillary Justice", author_id)
      create_book("Ancillary Sword", author_id)

      assert %{"success" => true, "data" => [author]} =
               run(%{"action" => "list_authors", "fields" => ["id", "bookCount"]})

      assert author["bookCount"] == 2
    end
  end

  describe "unknown fields" do
    test "a misspelled field is an error rather than silently dropped data" do
      create_author("Iain Banks", "iain@example.com")

      assert [error] =
               errors(run(%{"action" => "list_authors", "fields" => ["id", "naem"]}))

      assert error["type"] == "unknown_field"
      assert error["message"] =~ "naem"
    end

    test "a private attribute is not selectable" do
      assert [error] =
               errors(run(%{"action" => "list_todos", "fields" => ["title"]}))

      assert error["type"] == "unknown_field"
    end
  end

  describe "no fields requested" do
    test "still returns every public attribute" do
      create_author("Kim Stanley Robinson", "kim@example.com")

      assert %{"success" => true, "data" => [author]} =
               run(%{"action" => "list_authors"})

      assert author["name"] == "Kim Stanley Robinson"
      assert author["email"] == "kim@example.com"
    end
  end
end
