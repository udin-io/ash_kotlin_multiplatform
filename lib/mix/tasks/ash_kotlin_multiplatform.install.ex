# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshKotlinMultiplatform.Install do
    @shortdoc "Installs AshKotlinMultiplatform. Call it with `mix igniter.install ash_kotlin_multiplatform`"

    @moduledoc """
    #{@shortdoc}

    Writes the two things stage 3 of `ash_introspection` issue 23 needs and
    nothing else:

      * `MyApp.AshKotlinMultiplatformManifest`, a
        `AshKotlinMultiplatform.Manifest` module scoped to the app's `otp_app`.
      * `config :ash_kotlin_multiplatform, manifest: MyApp.AshKotlinMultiplatformManifest`,
        which `AshKotlinMultiplatform.Manifest.manifest_module/0` reads and
        raises without.

    Both are skipped when they already exist, so running it twice is safe and a
    hand-edited manifest module survives.

    The generated module deliberately carries no `:domains` option. That option
    suppresses the `Application.compile_env/3` compile edge, and a production
    manifest that stops noticing a domain added to config is the staleness this
    library exists to avoid.

    Adding the `AshKotlinMultiplatform.Rpc` extension to a domain, and
    `AshKotlinMultiplatform.Resource` to a resource, stays manual: which
    resources to publish to a Kotlin client is the one decision no installer can
    make.
    """

    use Igniter.Mix.Task

    @manifest_module "AshKotlinMultiplatformManifest"

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :ash,
        schema: [],
        composes: [],
        extra_args?: true
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)

      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_kotlin_multiplatform)
      |> create_manifest_module(app_name)
      |> configure_manifest()
      |> next_steps()
    end

    defp create_manifest_module(igniter, app_name) do
      module = Igniter.Project.Module.module_name(igniter, @manifest_module)

      case Igniter.Project.Module.module_exists(igniter, module) do
        {true, igniter} ->
          igniter

        {false, igniter} ->
          Igniter.Project.Module.create_module(
            igniter,
            module,
            "use AshKotlinMultiplatform.Manifest, otp_app: :#{app_name}"
          )
      end
    end

    # `configure_new/4` rather than `configure/4`: a consumer who already points
    # the key somewhere meant it.
    defp configure_manifest(igniter) do
      Igniter.Project.Config.configure_new(
        igniter,
        "config.exs",
        :ash_kotlin_multiplatform,
        [:manifest],
        Igniter.Project.Module.module_name(igniter, @manifest_module)
      )
    end

    defp next_steps(igniter) do
      Igniter.add_notice(igniter, """
      AshKotlinMultiplatform installed.

      Next:
      1. Add `AshKotlinMultiplatform.Rpc` to a domain and declare a `kotlin_rpc`
         block naming the actions your Kotlin client may call.
      2. Add `AshKotlinMultiplatform.Resource` to the resources it publishes.
      3. Run `mix ash_kotlin_multiplatform.codegen`.

      Docs: https://hexdocs.pm/ash_kotlin_multiplatform
      """)
    end
  end
else
  defmodule Mix.Tasks.AshKotlinMultiplatform.Install do
    @shortdoc "Installs AshKotlinMultiplatform. Requires igniter."

    @moduledoc @shortdoc

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      `mix ash_kotlin_multiplatform.install` needs igniter.

      Install it and try again:

          mix igniter.install ash_kotlin_multiplatform

      See https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
