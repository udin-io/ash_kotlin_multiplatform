# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshKotlinMultiplatform.InstallTest do
  @moduledoc """
  What the installer writes into a consumer's project.

  The manifest module and its config are the two things a consumer must not
  have to hand-write, and the two things everything else in stage 3 is useless
  without: `AshKotlinMultiplatform.Manifest.manifest_module/0` raises when the
  config is absent.
  """
  # Serial, and it has to be. `Igniter.compose_task/3` and `apply_igniter!/1`
  # read the test project's `config/config.exs` and apply it to the whole VM
  # with `Application.put_all_env/1` for the length of the task
  # (`deps/igniter/lib/igniter.ex:1697`), restoring it after. Inside that window
  # every other test reads `:ash_kotlin_multiplatform, :manifest` as the test
  # project's module. `Rpc.Pipeline.request_config/0` then calls
  # `persisted(:manifest)` on it and raises "is not a Spark DSL module" (#108).
  # Application env is VM-global with no per-process scope, so no setup/on_exit
  # pairing closes the window — only not running beside a reader does.
  use ExUnit.Case, async: false

  import Igniter.Test

  defp install(opts \\ []) do
    test_project(opts)
    |> Igniter.compose_task("ash_kotlin_multiplatform.install", ["--yes"])
  end

  describe "the manifest module" do
    test "is created, named after the app, using the Manifest DSL" do
      install()
      |> assert_creates(
        "lib/test/ash_kotlin_multiplatform_manifest.ex",
        """
        defmodule Test.AshKotlinMultiplatformManifest do
          use AshKotlinMultiplatform.Manifest, otp_app: :test
        end
        """
      )
    end

    # `:domains` suppresses the Application.compile_env/3 edge, so a module
    # declared with it stops noticing a domain added to config. The installer
    # must never write one — see AshKotlinMultiplatform.Manifest.
    test "never carries a :domains option" do
      contents =
        install()
        |> Igniter.Test.assert_creates("lib/test/ash_kotlin_multiplatform_manifest.ex")
        |> then(fn igniter ->
          Rewrite.source!(igniter.rewrite, "lib/test/ash_kotlin_multiplatform_manifest.ex")
          |> Rewrite.Source.get(:content)
        end)

      refute contents =~ "domains:"
    end

    test "is left alone when the consumer already wrote one" do
      [app_name: :test]
      |> test_project()
      |> Igniter.Project.Module.create_module(
        Test.AshKotlinMultiplatformManifest,
        "use AshKotlinMultiplatform.Manifest, otp_app: :test\n  # hand-edited"
      )
      |> apply_igniter!()
      |> Igniter.compose_task("ash_kotlin_multiplatform.install", ["--yes"])
      |> assert_unchanged("lib/test/ash_kotlin_multiplatform_manifest.ex")
    end
  end

  describe "config" do
    test "points :manifest at the created module" do
      # A bare test project has no config/config.exs, so the installer creates
      # it rather than patching one.
      install()
      |> assert_creates("config/config.exs", """
      import Config
      config :ash_kotlin_multiplatform, manifest: Test.AshKotlinMultiplatformManifest
      """)
    end

    test "patches an existing config rather than replacing it" do
      [
        app_name: :test,
        files: %{"config/config.exs" => "import Config\n\nconfig :test, foo: :bar\n"}
      ]
      |> test_project()
      |> Igniter.compose_task("ash_kotlin_multiplatform.install", ["--yes"])
      |> assert_has_patch("config/config.exs", """
      + |config :ash_kotlin_multiplatform, manifest: Test.AshKotlinMultiplatformManifest
      """)
    end

    test "does not overwrite a manifest the consumer already configured" do
      [app_name: :test]
      |> test_project()
      |> Igniter.Project.Config.configure(
        "config.exs",
        :ash_kotlin_multiplatform,
        [:manifest],
        MyApp.Chosen
      )
      |> apply_igniter!()
      |> Igniter.compose_task("ash_kotlin_multiplatform.install", ["--yes"])
      |> assert_unchanged("config/config.exs")
    end
  end
end
