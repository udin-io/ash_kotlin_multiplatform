# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshKotlinMultiplatform.CodegenTest do
  @moduledoc """
  Every way `--check`/`--dry-run`/neither can end, behaviour only. #26.
  """
  use ExUnit.Case, async: false

  alias Mix.Tasks.AshKotlinMultiplatform.Codegen

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    output_file =
      Path.join(
        System.tmp_dir!(),
        "ash_kotlin_codegen_test_#{System.unique_integer([:positive])}.kt"
      )

    on_exit(fn -> File.rm(output_file) end)

    %{output_file: output_file}
  end

  test "1: no flags, output missing writes the new content and prints Generated <path>", %{
    output_file: output_file
  } do
    refute File.exists?(output_file)

    Codegen.run(["--output", output_file])

    assert File.exists?(output_file)
    assert_received {:mix_shell, :info, ["Generating Kotlin code for" <> _]}
    assert_received {:mix_shell, :info, [text]}
    assert text =~ "Generated #{output_file}"
  end

  test "1b: no flags, output stale, overwrites it", %{output_file: output_file} do
    File.write!(output_file, "stale content")

    Codegen.run(["--output", output_file])

    refute File.read!(output_file) == "stale content"
  end

  test "2: --check, file already matches: exit 0, nothing written, nothing printed", %{
    output_file: output_file
  } do
    Codegen.run(["--output", output_file])
    generated = File.read!(output_file)
    assert_received {:mix_shell, :info, ["Generating Kotlin code for" <> _]}
    assert_received {:mix_shell, :info, ["Generated" <> _]}

    Codegen.run(["--output", output_file, "--check"])

    assert File.read!(output_file) == generated
    assert_received {:mix_shell, :info, ["Generating Kotlin code for" <> _]}
    refute_received {:mix_shell, :info, ["Generated" <> _]}
  end

  test "3: --check, file differs: raises PendingCodegen, exit non-zero, nothing written", %{
    output_file: output_file
  } do
    File.write!(output_file, "stale content")

    assert_raise Ash.Error.Framework.PendingCodegen, fn ->
      Codegen.run(["--output", output_file, "--check"])
    end

    assert File.read!(output_file) == "stale content"
  end

  test "4: --check, file does not exist yet: same as #3", %{output_file: output_file} do
    refute File.exists?(output_file)

    assert_raise Ash.Error.Framework.PendingCodegen, fn ->
      Codegen.run(["--output", output_file, "--check"])
    end

    refute File.exists?(output_file)
  end

  test "5: --dry-run, file already matches: exit 0, nothing written, nothing printed", %{
    output_file: output_file
  } do
    Codegen.run(["--output", output_file])
    generated = File.read!(output_file)
    assert_received {:mix_shell, :info, ["Generating Kotlin code for" <> _]}
    assert_received {:mix_shell, :info, ["Generated" <> _]}

    Codegen.run(["--output", output_file, "--dry-run"])

    assert File.read!(output_file) == generated
    assert_received {:mix_shell, :info, ["Generating Kotlin code for" <> _]}
    refute_received {:mix_shell, :info, [_msg]}
  end

  test "6: --dry-run, file differs: prints the full new file to stdout, nothing written", %{
    output_file: output_file
  } do
    File.write!(output_file, "stale content")

    Codegen.run(["--output", output_file, "--dry-run"])

    assert File.read!(output_file) == "stale content"
    assert_received {:mix_shell, :info, ["Generating Kotlin code for" <> _]}
    assert_received {:mix_shell, :info, [text]}
    assert text =~ "package " or text =~ "object "
  end

  test "7: --check and --dry-run both given, file differs: --check wins, nothing printed", %{
    output_file: output_file
  } do
    File.write!(output_file, "stale content")

    assert_raise Ash.Error.Framework.PendingCodegen, fn ->
      Codegen.run(["--output", output_file, "--check", "--dry-run"])
    end

    assert_received {:mix_shell, :info, ["Generating Kotlin code for" <> _]}
    refute_received {:mix_shell, :info, [_msg]}
    assert File.read!(output_file) == "stale content"
  end

  test "9: mix ash.codegen --check forwards through Rpc.codegen/1 and raises the same way", %{
    output_file: output_file
  } do
    File.write!(output_file, "stale content")

    assert_raise Ash.Error.Framework.PendingCodegen, fn ->
      AshKotlinMultiplatform.Rpc.codegen(["--output", output_file, "--check"])
    end
  end

  test "10: mix ash.codegen forwards --name <nil> and it is ignored, no crash", %{
    output_file: output_file
  } do
    Codegen.run(["--output", output_file, "--name", nil])

    assert File.exists?(output_file)
  end

  # #33: a name clash (Declarations.check/1) reaches generate_kotlin_code/2
  # as the same {:error, reason} a missing RPC resource or a failed
  # verifier already returns, so the task's existing {:error, reason} ->
  # Mix.shell().error(...); exit({:shutdown, 1}) branch already covers it
  # — no new branch, and this guards that staying true.
  test "11: --check on a clash exits non-zero, prints both sources, writes nothing", %{
    output_file: output_file
  } do
    previous = Application.get_env(:ash_kotlin_multiplatform, :ash_domains)

    Application.put_env(:ash_kotlin_multiplatform, :ash_domains, [
      AshKotlinMultiplatform.Test.IdentifierCollisions.ClashDomain
    ])

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:ash_kotlin_multiplatform, :ash_domains)
        value -> Application.put_env(:ash_kotlin_multiplatform, :ash_domains, value)
      end
    end)

    caught =
      catch_exit(Codegen.run(["--output", output_file, "--check"]))

    assert caught == {:shutdown, 1}
    refute File.exists?(output_file)
    assert_received {:mix_shell, :info, ["Generating Kotlin code for" <> _]}
    assert_received {:mix_shell, :error, [text]}
    assert text =~ "WidgetStatus"
    assert text =~ "AshKotlinMultiplatform.Test.IdentifierCollisions.ClashOne"
    assert text =~ "AshKotlinMultiplatform.Test.IdentifierCollisions.ClashTwo"
  end
end
