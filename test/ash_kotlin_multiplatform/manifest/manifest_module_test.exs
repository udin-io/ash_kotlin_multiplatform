# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.ManifestModuleTest do
  @moduledoc """
  Code generation requires `config :ash_kotlin_multiplatform, :manifest` (#84).

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
  end
end
