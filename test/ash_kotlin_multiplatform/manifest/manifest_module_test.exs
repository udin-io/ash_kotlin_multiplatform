# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.ManifestModuleTest do
  @moduledoc """
  Code generation requires `config :ash_kotlin_multiplatform, :manifest` (#84),
  and since `ash_introspection#23` stage 5a so does a request.

  Synchronous, because each test deletes that key from the application env,
  which every other test reads. ExUnit runs synchronous modules after the
  asynchronous ones have finished.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Manifest

  setup do
    original = Application.fetch_env!(:ash_kotlin_multiplatform, :manifest)
    Application.delete_env(:ash_kotlin_multiplatform, :manifest)
    on_exit(fn -> Application.put_env(:ash_kotlin_multiplatform, :manifest, original) end)
  end

  describe "with no :manifest configured" do
    test "manifest_module/0 names the config line and the installer" do
      error = assert_raise ArgumentError, fn -> Manifest.manifest_module() end

      assert error.message =~
               "config :ash_kotlin_multiplatform, manifest: MyApp.AshKotlinMultiplatformManifest"

      assert error.message =~ "mix igniter.install ash_kotlin_multiplatform"
    end

    test "Kotlin code generation raises" do
      assert_raise ArgumentError, ~r/No `:manifest` module configured/, fn ->
        AshKotlinMultiplatform.Rpc.Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
      end
    end

    test "Swift code generation raises" do
      assert_raise ArgumentError, ~r/No `:manifest` module configured/, fn ->
        AshKotlinMultiplatform.Swift.Codegen.generate_swift_code(:ash_kotlin_multiplatform)
      end
    end

    # A raise, not an error response. `Runner.discover_action/2` reads the
    # manifest's `:rpc_action_lookup`, so there is nowhere left to look for the
    # action name. An error response would say `action_not_found` and send the
    # operator hunting for a missing `rpc_action`; the raise names the config
    # line instead. An app in this state could never have generated a client to
    # send the request with, because code generation raises the same way.
    test "a request raises rather than answering action_not_found" do
      error =
        assert_raise ArgumentError, fn ->
          AshKotlinMultiplatform.Rpc.Runner.run_action(:ash_kotlin_multiplatform, %{
            "action" => "list_todos"
          })
        end

      assert error.message =~ "No `:manifest` module configured"
    end

    test "validation raises the same way" do
      assert_raise ArgumentError, ~r/No `:manifest` module configured/, fn ->
        AshKotlinMultiplatform.Rpc.Runner.validate_action(:ash_kotlin_multiplatform, %{
          "action" => "create_todo",
          "input" => %{"title" => "x"}
        })
      end
    end
  end
end
