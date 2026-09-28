# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshKotlinMultiplatform.Upgrade do
    @shortdoc "Prints each breaking release's notice"

    # `mix igniter.upgrade ash_kotlin_multiplatform` resolves this task by
    # `Mix.Task.get("ash_kotlin_multiplatform.upgrade")`, which requires the
    # module to be named `Mix.Tasks.AshKotlinMultiplatform.Upgrade` — no other
    # name resolves, and Igniter reports the package as missing an upgrade
    # task with no other error (ash_introspection #99, this ticket #124).
    #
    # Each entry prints straight to `Mix.shell()` instead of going through
    # `Igniter.add_notice/2`. ash_introspection #99 measured that
    # `Igniter.CopiedTasks.upgrade/1` (the path `igniter_new`'s archive runs)
    # never calls `Igniter.do_or_dry_run/2`, so a notice added the ordinary
    # way is collected and silently discarded under that setup.
    @moduledoc false

    use Igniter.Mix.Task

    @breaking_0_3_0_notice """
    ash_kotlin_multiplatform 0.3.0 changes the RPC error payload a client
    reads.

      * `type` and `shortMessage` now come from the shared core error
        handling, not this library's own formatting. `validation_error`
        becomes `invalid_attribute`, and a message such as "Validation
        failed" becomes "required". The full before/after table is in
        `CHANGELOG.md`'s Unreleased section.
      * A new `result_unavailable` type covers a result that ran but could
        not be sent to the client.
      * `field` is unchanged: a client reading only `field` today needs no
        change.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_kotlin_multiplatform,
        example: "mix ash_kotlin_multiplatform.upgrade 0.2.0 0.3.0",
        positional: [:from, :to]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      positional = igniter.args.positional

      upgrades = %{
        "0.3.0" => [&notify_0_3_0_breaks/2]
      }

      igniter
      |> Igniter.Upgrades.run(positional.from, positional.to, upgrades, [])
      |> fallback_notice(positional.from, positional.to, upgrades)
    end

    @doc false
    def notify_0_3_0_breaks(igniter, _opts) do
      notify(igniter, @breaking_0_3_0_notice)
    end

    defp notify(igniter, text) do
      Mix.shell().info(text)
      igniter
    end

    # A developer stuck on a copy of this task older than the release they
    # are upgrading to (no `igniter_new` archive installed, so the old copy
    # stays loaded — ash_introspection #99) sees nothing from `upgrades`: its
    # keys stop at this copy's newest release. Naming the direct command is
    # the only way to reach them.
    defp fallback_notice(igniter, from, to, upgrades) do
      newest = upgrades |> Map.keys() |> Enum.max(Version)

      if Version.compare(to, newest) == :gt do
        notify(igniter, """
        This copy of the ash_kotlin_multiplatform upgrade task knows
        releases up to #{newest}. Run `mix ash_kotlin_multiplatform.upgrade
        #{from} #{to}` now to see what #{to} breaks.
        """)
      else
        igniter
      end
    end
  end
else
  defmodule Mix.Tasks.AshKotlinMultiplatform.Upgrade do
    @moduledoc false

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_kotlin_multiplatform.upgrade' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
