# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerOutputValueFormattingTest do
  @moduledoc """
  Stage 4 must format values by their Ash type, not just rename field names.

  #71: `Rpc.Runner` called `Pipeline.format_output/1`, which renames keys at
  every depth and never looks at a value. `AshIntrospection.Rpc.ValueFormatter`
  — the module that turns `%Ash.Vector{}` into a list of floats — was reachable
  only through `Pipeline.format_output/2`, which nothing called. A vector
  attribute therefore reached `Jason` as the packed binary `%Ash.Vector{}`
  carries and raised `Jason.EncodeError`, so every request touching
  `Todo.embedding` returned a 500.

  The assertions encode the response rather than reading a value out of the map.
  That is deliberate: the bug was invisible to every assertion that stopped at
  the Elixir term, because the term is well-formed right up to the moment the
  encoder walks it. `Phoenix.json_library/0` is the encoder
  `AshKotlinMultiplatform.Phoenix.Controller` hands the result to, so encoding
  through it here tests the bytes a Kotlin client actually receives.

  The list and page cases are here because they are what the naive fix breaks.
  Measured 2026-09-11 on `ash_introspection` 0.3.0: routing stage 4 through
  `format_output_with_request/3` made every record in a list or page come back
  with internal atom keys, failing six tests in
  `runner_field_selection_test.exs`. 0.4.0 fixed that upstream and this file
  keeps it fixed here.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  defp encode(response), do: Phoenix.json_library().encode!(response)

  defp decode(response), do: response |> encode() |> Phoenix.json_library().decode!()

  describe "a vector attribute" do
    test "encodes as a JSON array of numbers, not as its packed binary" do
      response =
        run(%{
          "action" => "create_todo",
          "input" => %{"title" => "Index me", "embedding" => [0.25, -1.5, 3.0]}
        })

      assert %{"success" => true, "data" => %{"embedding" => embedding}} = decode(response)
      assert embedding == [0.25, -1.5, 3.0]
    end

    test "the response encodes at all" do
      response =
        run(%{
          "action" => "create_todo",
          "input" => %{"title" => "Index me", "embedding" => [0.25, -1.5, 3.0]}
        })

      json = encode(response)

      assert json =~ ~s("embedding":[0.25,-1.5,3.0])
    end

    test "a nil vector stays null rather than becoming an empty object" do
      response = run(%{"action" => "create_todo", "input" => %{"title" => "No vector"}})

      assert %{"success" => true, "data" => %{"embedding" => nil}} = decode(response)
    end
  end

  describe "multi-record reads keep their field-name formatting" do
    setup do
      for name <- ["Ada Lovelace", "Grace Hopper"] do
        run(%{
          "action" => "create_author",
          "input" => %{"name" => name, "email" => "#{name}@example.com"}
        })
      end

      :ok
    end

    test "every record in a list read is formatted, not just the first" do
      response = run(%{"action" => "list_authors", "fields" => ["id", "name", "bookCount"]})

      assert %{"success" => true, "data" => records} = decode(response)
      assert length(records) >= 2

      for record <- records do
        assert Enum.sort(Map.keys(record)) == ["bookCount", "id", "name"]
      end
    end

    test "every record inside a page read is formatted too" do
      response =
        run(%{
          "action" => "keyset_authors",
          "fields" => ["id", "name"],
          "page" => %{"limit" => 2}
        })

      assert %{"success" => true, "data" => page} = decode(response)
      assert %{"hasMore" => _, "results" => results} = page
      assert length(results) == 2

      for record <- results do
        assert Enum.sort(Map.keys(record)) == ["id", "name"]
      end
    end
  end
end
