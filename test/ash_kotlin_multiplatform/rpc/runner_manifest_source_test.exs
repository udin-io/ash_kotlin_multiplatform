# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerManifestSourceTest do
  @moduledoc """
  The manifest is the request path's source of truth, not a passenger on it
  (`ash_introspection#23` stage 5a, PR 4).

  Carrying a manifest and reading it are different claims, and only the second
  is worth asserting. A test that configures a manifest agreeing with the live
  domain passes whichever one the code reads. So every test here points
  `config :ash_kotlin_multiplatform, manifest:` at a manifest that DISAGREES
  with live introspection, and asserts the response follows the manifest.

  Synchronous, because each test repoints that config key and every other test
  reads it. ExUnit runs synchronous modules after the asynchronous ones.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Rpc.Runner
  alias AshKotlinMultiplatform.Test

  setup do
    original = Application.fetch_env!(:ash_kotlin_multiplatform, :manifest)
    on_exit(fn -> Application.put_env(:ash_kotlin_multiplatform, :manifest, original) end)
    :ok
  end

  describe "a manifest scoped to one domain" do
    setup do
      Application.put_env(:ash_kotlin_multiplatform, :manifest, Test.ScopedManifest)
      :ok
    end

    test "an rpc_action it does not name is action_not_found" do
      assert [error] = errors(run(%{"action" => "list_todos"}))
      assert error["type"] == "action_not_found"
      assert error["message"] == "RPC action 'list_todos' not found"
    end

    # The other half of the claim above. Without it the first test passes on a
    # request path that answers `action_not_found` to everything.
    test "an rpc_action it does name runs, though no configured domain declares it" do
      refute Test.ScopedDomain in Ash.Info.domains(:ash_kotlin_multiplatform)

      assert %{"success" => true, "data" => books} =
               run(%{"action" => "scoped_list_books", "fields" => ["id"]})

      assert is_list(books)
    end

    test "the live domain scan this replaced would have answered the opposite" do
      names =
        for %{rpc_actions: rpc_actions} <-
              AshKotlinMultiplatform.Rpc.Info.kotlin_rpc(Test.Domain),
            rpc_action <- rpc_actions,
            do: to_string(rpc_action.name)

      assert "list_todos" in names
      refute Map.has_key?(Manifest.rpc_action_lookup(Test.ScopedManifest), "list_todos")
    end
  end

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  defp errors(response) do
    assert %{"success" => false, "errors" => errors} = response
    errors
  end
end
