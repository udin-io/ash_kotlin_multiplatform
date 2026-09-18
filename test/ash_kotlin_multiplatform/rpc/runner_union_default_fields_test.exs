# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerUnionDefaultFieldsTest do
  @moduledoc """
  A generic action returning a union answers a request with no `fields` with
  the active member's own default fields (#96).

  Which member is active is known only at result time, from
  `%Ash.Union{type:}`. So the runner cannot name the fields in advance: it
  sends an empty extraction template, and
  `AshIntrospection.Rpc.ResultProcessor.extract_union_value/4` gives that
  member whatever #88 and #95 give its type — a resource member its public
  attributes, a typed map member its declared fields, a scalar member the
  value.

  Before the fix `Runner.select_fields/3` sent Book's attribute names for a
  union return, which no member has, so the response carried `nil` for a
  single union and `[]` for a list. Measured on ash_introspection 0.5.1,
  2026-09-18.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  defp note(member), do: run(%{"action" => "book_note", "input" => %{"member" => member}})

  test "an embedded resource member sends that resource's attributes" do
    assert note("note") ==
             %{"success" => true, "data" => %{"note" => %{"label" => "Noted"}}}
  end

  test "a typed map member sends its declared fields" do
    assert note("tally") ==
             %{
               "success" => true,
               "data" => %{"tally" => %{"bookCount" => 2, "topTitle" => "Kindred"}}
             }
  end

  test "a scalar member sends the value" do
    assert note("headline") == %{"success" => true, "data" => %{"headline" => "Front page"}}
  end

  test "a list of unions sends every item, each by its own member" do
    assert run(%{"action" => "book_notes"}) ==
             %{
               "success" => true,
               "data" => [
                 %{"note" => %{"label" => "Noted"}},
                 %{"tally" => %{"bookCount" => 2, "topTitle" => "Kindred"}},
                 %{"headline" => "Front page"}
               ]
             }
  end

  # The other half of the pair. 0.5.1 is what made an explicit selection work
  # at all, so a fix to the no-`fields` default that broke it would look like
  # progress.
  test "naming every member keeps working" do
    for member <- ["note", "tally", "headline"] do
      explicit =
        run(%{
          "action" => "book_note",
          "input" => %{"member" => member},
          "fields" => [
            %{"note" => ["label"]},
            %{"tally" => ["bookCount", "topTitle"]},
            "headline"
          ]
        })

      assert explicit == note(member)
    end
  end

  test "a list of unions with every member named keeps working" do
    explicit =
      run(%{
        "action" => "book_notes",
        "fields" => [
          %{"note" => ["label"]},
          %{"tally" => ["bookCount", "topTitle"]},
          "headline"
        ]
      })

    assert explicit == run(%{"action" => "book_notes"})
  end
end
