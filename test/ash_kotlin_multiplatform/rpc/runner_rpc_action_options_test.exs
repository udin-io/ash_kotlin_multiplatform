# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerRpcActionOptionsTest do
  @moduledoc """
  The `rpc_action` options that change what a request may carry, through
  `Runner.run_action/3` — the only entry point a client has.

  Issue #25: the shared core already honoured `get?`, applied `get_by`, read
  `identities` and branched on `not_found_error?`, and the `kotlin_rpc` DSL
  declared none of them. Every one of those branches was unreachable, so a
  single-record read had no way to say which record it wanted: it ran as a list
  read and returned the whole table.

  `fetch_author` and `find_author` use the plain `:read` action, so what they
  prove is the DSL wiring rather than Ash's own `get? true` — `get_author`
  (action `:by_id`) is the action-level path and is covered elsewhere.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  defp create_author(name, email) do
    assert %{"success" => true, "data" => author} =
             run(%{
               "action" => "create_author",
               "input" => %{"name" => name, "email" => email},
               "fields" => ["id"]
             })

    author["id"]
  end

  defp error(response) do
    assert %{"success" => false, "errors" => [error]} = response
    error
  end

  defp unique_email, do: "author-#{System.unique_integer([:positive])}@example.com"

  describe "get_by" do
    test "selects the one record the client named" do
      email = unique_email()
      id = create_author("Ursula Le Guin", email)
      _other = create_author("Octavia Butler", unique_email())

      assert %{"success" => true, "data" => author} =
               run(%{
                 "action" => "fetch_author",
                 "getBy" => %{"id" => id},
                 "fields" => ["id", "name"]
               })

      assert author == %{"id" => id, "name" => "Ursula Le Guin"}
    end

    test "returns one record rather than a list" do
      id = create_author("Ursula Le Guin", unique_email())

      assert %{"success" => true, "data" => data} =
               run(%{"action" => "fetch_author", "getBy" => %{"id" => id}, "fields" => ["id"]})

      refute is_list(data)
    end

    test "names the fields that are missing" do
      assert %{"type" => "missing_required_input", "field" => "id"} =
               error(run(%{"action" => "fetch_author"}))
    end

    test "refuses a field the action did not configure" do
      id = create_author("Ursula Le Guin", unique_email())

      assert %{"type" => "unexpected_get_by_fields", "field" => "email"} =
               error(
                 run(%{
                   "action" => "fetch_author",
                   "getBy" => %{"id" => id, "email" => "someone@example.com"}
                 })
               )
    end

    # `Ash.Query.do_filter/2` reads a map operand as an operator expression, so
    # an unchecked getBy value turns an exact lookup into an arbitrary
    # predicate. The core rejects it; this proves the rejection reaches a client.
    test "refuses a non-scalar value" do
      assert %{"type" => "invalid_get_by"} =
               error(run(%{"action" => "fetch_author", "getBy" => %{"id" => %{"gt" => "a"}}}))
    end

    test "refuses getBy on an action that configured none" do
      assert %{"type" => "unexpected_get_by_fields"} =
               error(run(%{"action" => "list_authors", "getBy" => %{"id" => "anything"}}))
    end
  end

  describe "not_found_error?" do
    test "true is an error when nothing matches" do
      assert %{"type" => "not_found"} =
               error(
                 run(%{"action" => "fetch_author", "getBy" => %{"id" => Ash.UUID.generate()}})
               )
    end

    test "false is a successful null when nothing matches" do
      assert %{"success" => true, "data" => nil} =
               run(%{"action" => "find_author", "getBy" => %{"email" => unique_email()}})
    end

    test "false still returns the record when one matches" do
      email = unique_email()
      create_author("Ursula Le Guin", email)

      assert %{"success" => true, "data" => %{"name" => "Ursula Le Guin"}} =
               run(%{
                 "action" => "find_author",
                 "getBy" => %{"email" => email},
                 "fields" => ["name"]
               })
    end
  end

  describe "enable_filter? and enable_sort?" do
    test "both are accepted by default" do
      assert %{"success" => true} =
               run(%{
                 "action" => "list_books",
                 "filter" => %{"title" => "Dune"},
                 "sort" => "title"
               })
    end

    # Rejected rather than dropped: a stale client that still sends `filter`
    # would otherwise be handed the whole table with no way to know it asked for
    # a subset.
    test "enable_filter? false refuses a filter" do
      assert %{"type" => "filter_not_supported"} =
               error(
                 run(%{"action" => "list_books_unfiltered", "filter" => %{"title" => "Dune"}})
               )
    end

    test "enable_filter? false still accepts a sort" do
      assert %{"success" => true} =
               run(%{"action" => "list_books_unfiltered", "sort" => "title"})
    end

    test "enable_sort? false refuses a sort" do
      assert %{"type" => "sort_not_supported"} =
               error(run(%{"action" => "list_books_fixed_order", "sort" => "title"}))
    end

    test "enable_sort? false still accepts a filter" do
      assert %{"success" => true} =
               run(%{"action" => "list_books_fixed_order", "filter" => %{"title" => "Dune"}})
    end
  end

  describe "identity on a read" do
    # The core refuses it rather than dropping it, and the message names the
    # replacement. Worth a test here because the runner has to route that error
    # through the shared builder to keep the suggestion.
    test "is refused and points at getBy" do
      assert %{"type" => "identity_not_supported", "message" => message} =
               error(run(%{"action" => "list_authors", "identity" => Ash.UUID.generate()}))

      assert message =~ "getBy"
    end
  end
end
