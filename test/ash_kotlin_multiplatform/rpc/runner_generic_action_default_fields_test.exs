# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerGenericActionDefaultFieldsTest do
  @moduledoc """
  A request with no `fields` gets the public attributes of the resource the
  action returns (#88).

  Before #88 the runner built that default from the resource that OWNS the
  action. `Book.summarize` returns `Summary`, so a request without `fields`
  answered with Book's five keys, every one `nil`. Generated Kotlin decodes
  that into `Summary(label=null)` without an error, because `ashRpcJson`
  ignores unknown keys.

  A generic action returning a map that declares its `fields` had the same
  bug and gets those field names. A map with no declared fields, and any
  other return, is sent as before.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  test "an embedded resource return sends that resource's attributes" do
    assert %{"success" => true, "data" => data} =
             run(%{
               "action" => "summarize_book",
               "input" => %{"opts" => %{"label" => "Short"}}
             })

    assert data == %{"label" => "Short"}
  end

  test "a list of an embedded resource sends a list of its attributes" do
    assert %{"success" => true, "data" => data} = run(%{"action" => "summarize_all"})

    assert data == [%{"label" => "One"}, %{"label" => "Two"}]
  end

  test "a :struct instance_of return sends that resource's attributes" do
    assert %{"success" => true, "data" => data} = run(%{"action" => "sample_author"})

    assert data == %{
             "id" => "00000000-0000-0000-0000-000000000001",
             "name" => "Sample",
             "email" => "sample@example.com",
             "addressLine1" => nil
           }
  end

  test "a map with declared fields sends those fields" do
    assert %{"success" => true, "data" => data} = run(%{"action" => "tally_books"})

    assert data == %{"bookCount" => 2, "topTitle" => "Kindred"}
  end

  test "a map with no declared fields is sent as it is" do
    assert %{"success" => true, "data" => data} = run(%{"action" => "raw_book_stats"})

    assert data == %{"shelf_count" => 3}
  end

  test "a read still sends its own resource's attributes" do
    assert %{"success" => true, "data" => %{"id" => author_id}} =
             run(%{
               "action" => "create_author",
               "input" => %{"name" => "Default Read", "email" => "read@example.com"},
               "fields" => ["id"]
             })

    assert %{"success" => true, "data" => authors} = run(%{"action" => "list_authors"})
    author = Enum.find(authors, &(&1["id"] == author_id))

    assert author == %{
             "id" => author_id,
             "name" => "Default Read",
             "email" => "read@example.com",
             "addressLine1" => nil
           }
  end
end
