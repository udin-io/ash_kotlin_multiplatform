# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshKotlinMultiplatform.UpgradeTest do
  @moduledoc """
  #123 changes the RPC error payload's `type`/`shortMessage` values and adds
  `result_unavailable`. This task is the notice a developer sees when they
  run `mix igniter.upgrade ash_kotlin_multiplatform` across that release.

  Notices print straight to `Mix.shell()` rather than through
  `Igniter.add_notice/2`: ash_introspection #99 measured that the notice
  queue is silently dropped under the usual `igniter_new` archive setup.
  """
  use ExUnit.Case, async: false

  import Igniter.Test

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp upgrade(from, to) do
    test_project()
    |> Igniter.compose_task("ash_kotlin_multiplatform.upgrade", [from, to])
  end

  test "mix igniter.upgrade resolves this task by name" do
    mod = Mix.Task.get("ash_kotlin_multiplatform.upgrade")
    assert mod
    assert function_exported?(mod, :info, 2)
  end

  test "prints the 0.3.0 breaking notice to the shell when 0.3.0 is in range" do
    upgrade("0.2.0", "0.3.0")

    assert_received {:mix_shell, :info, [text]}
    assert text =~ "result_unavailable"
    assert text =~ "field` is unchanged"
  end

  test "prints nothing when the range holds no key" do
    upgrade("0.1.0", "0.2.0")
    refute_received {:mix_shell, :info, _}
  end

  describe "the fallback for a copy that does not know the target release" do
    test "prints when to is newer than the newest key this copy knows" do
      upgrade("0.3.0", "0.4.0")

      assert_received {:mix_shell, :info, [text]}
      normalized = String.replace(text, "\n", " ")
      assert normalized =~ "mix ash_kotlin_multiplatform.upgrade 0.3.0 0.4.0"
    end

    test "does not print when to equals the newest key" do
      upgrade("0.2.0", "0.3.0")

      assert_received {:mix_shell, :info, [_breaking_notice]}
      refute_received {:mix_shell, :info, _}
    end

    test "does not print when to is older than the newest key" do
      upgrade("0.1.0", "0.2.0")
      refute_received {:mix_shell, :info, _}
    end
  end
end
