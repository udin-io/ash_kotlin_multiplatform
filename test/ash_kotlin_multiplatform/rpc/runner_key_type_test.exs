# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerKeyTypeTest do
  @moduledoc """
  Issue #77 through `Runner.run_action/3`: the shape of a parsed map follows
  the request, never the atom table.

  `Ash.Page.page_opts/1` rejects an unknown page option by inspecting the map
  it was handed (`deps/ash/lib/ash/page/page.ex:16`), so the page error message
  is the one place a client can read a parsed map's key types back. On `main`
  that message flipped between `%{limit: 2, some_key: 1}` and
  `%{:limit => 2, "some_key" => 1}` for the same request, depending on whether
  anything in the VM had interned `:some_key`.

  These cases are synchronous: `String.to_atom/1` here would otherwise change
  what a concurrent module sees.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Rpc.Runner

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  defp message_of(%{"errors" => [%{"message" => message} | _]}), do: message
  defp message_of(_response), do: ""

  defp page_error_message(key), do: page_error_message_for(%{"limit" => 2, key => 1})

  defp page_error_message_for(page) do
    assert %{"success" => false, "errors" => [%{"message" => message}]} =
             run(%{"action" => "list_authors", "page" => page, "fields" => ["id"]})

    message
  end

  describe "an unknown page key" do
    test "reaches Ash as a string even when the VM has interned it" do
      _ = String.to_atom("page_key_type_probe")

      message = page_error_message("page_key_type_probe")

      assert message =~ ~s("page_key_type_probe" => 1)
      refute message =~ "page_key_type_probe: 1"
    end

    test "reads the same whether or not the VM has interned it" do
      _ = String.to_atom("page_key_type_interned")

      interned = page_error_message("page_key_type_interned")
      fresh = page_error_message("page_key_type_fresh_zz")

      assert String.replace(interned, "page_key_type_interned", "NAME") ==
               String.replace(fresh, "page_key_type_fresh_zz", "NAME")
    end
  end

  describe "a known page key" do
    test "still reaches Ash as the atom the option is named with" do
      assert %{"success" => true} =
               run(%{"action" => "list_authors", "page" => %{"limit" => 2}, "fields" => ["id"]})
    end
  end

  describe "the page option names the runner resolves" do
    test "are exactly the ones Ash declares" do
      declared =
        (Keyword.keys(Ash.Page.Keyset.page_opts()) ++ Keyword.keys(Ash.Page.Offset.page_opts()))
        |> Enum.uniq()
        |> Enum.sort()

      assert declared == [:after, :before, :count, :filter, :limit, :offset]
    end

    test "each one reaches Ash as its own option rather than as an unknown key" do
      for {name, value} <- [
            {"after", "cursor"},
            {"before", "cursor"},
            {"count", true},
            {"filter", nil},
            {"limit", 2},
            {"offset", 0}
          ] do
        response =
          run(%{"action" => "list_authors", "page" => %{name => value}, "fields" => ["id"]})

        refute message_of(response) =~ "is not a valid page option",
               "#{name} was rejected as an unknown page option"
      end
    end
  end

  describe "an untyped map attribute" do
    test "comes back with every key a string, at every depth" do
      _ = String.to_atom("untyped_key_type_probe")

      assert %{"success" => true, "data" => data} =
               run(%{
                 "action" => "create_todo",
                 "input" => %{
                   "title" => "Key types",
                   "metadata" => %{
                     "untyped_key_type_probe" => 1,
                     "untyped_key_type_fresh_zz" => 2,
                     "nested" => %{"untyped_key_type_probe" => 3}
                   }
                 },
                 "fields" => ["id", "metadata"]
               })

      assert Enum.all?(Map.keys(data["metadata"]), &is_binary/1)
      assert Enum.all?(Map.keys(data["metadata"]["nested"]), &is_binary/1)
    end
  end
end
