# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshKotlinMultiplatform.Codegen do
  @shortdoc "Generates Kotlin code from Ash resources"

  @moduledoc """
  Generates Kotlin code from Ash resources configured with AshKotlinMultiplatform extensions.

  ## Usage

      mix ash_kotlin_multiplatform.codegen [--check | --dry-run]

  ## Options

    * `--output` - Output file path (default: configured in :ash_kotlin_multiplatform, :output_file)
    * `--package` - Package name (default: configured in :ash_kotlin_multiplatform, :package_name)
    * `--app` - OTP app name (default: current mix project app)
    * `--check` - Write nothing. Raise `Ash.Error.Framework.PendingCodegen` when the
      generated content would differ from what is on disk (or when the output file
      does not exist yet).
    * `--dry-run` - Write nothing. Print the new content to stdout when it would
      differ from what is on disk.

  Given both, `--check` wins: it raises and prints nothing.

  ## Examples

      # Generate with defaults
      mix ash_kotlin_multiplatform.codegen

      # Specify output file
      mix ash_kotlin_multiplatform.codegen --output lib/generated/AshRpc.kt

      # Specify package name
      mix ash_kotlin_multiplatform.codegen --package com.mycompany.myapp

      # Fail CI when the committed file is stale
      mix ash_kotlin_multiplatform.codegen --check

      # Preview the pending change
      mix ash_kotlin_multiplatform.codegen --dry-run
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    # Parsing stays lenient (no `:strict`) on purpose: `mix ash.codegen` appends
    # `--name <value-or-nil>` to argv before forwarding to every extension's
    # codegen task. `OptionParser.parse/2` never raises on an unrecognized
    # switch regardless of `strict:` (only `parse!/2` does), so that extra
    # switch is silently dropped into the ignored third tuple element.
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          package: :string,
          app: :string,
          check: :boolean,
          dry_run: :boolean
        ]
      )

    otp_app = get_otp_app(opts)
    output_file = Keyword.get(opts, :output) || AshKotlinMultiplatform.output_file()

    codegen_opts =
      if package = Keyword.get(opts, :package) do
        [package_name: package]
      else
        []
      end

    Mix.shell().info("Generating Kotlin code for #{otp_app}...")

    case AshKotlinMultiplatform.Rpc.Codegen.generate_kotlin_code(otp_app, codegen_opts) do
      {:ok, kotlin_code} ->
        handle_output(output_file, kotlin_code, opts)

      {:error, reason} ->
        Mix.shell().error("Code generation failed: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp handle_output(output_file, kotlin_code, opts) do
    cond do
      opts[:check] ->
        if changed?(output_file, kotlin_code) do
          raise Ash.Error.Framework.PendingCodegen, diff: %{output_file => kotlin_code}
        end

        :ok

      opts[:dry_run] ->
        if changed?(output_file, kotlin_code), do: Mix.shell().info(kotlin_code)
        :ok

      true ->
        output_file
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(output_file, kotlin_code)

        Mix.shell().info("Generated #{output_file}")
        :ok
    end
  end

  # Only `--check` and `--dry-run` need to know whether the content changed —
  # the default path writes unconditionally either way, so it skips this read.
  defp changed?(output_file, kotlin_code) do
    current = if File.exists?(output_file), do: File.read!(output_file), else: ""
    kotlin_code != current
  end

  defp get_otp_app(opts) do
    case Keyword.get(opts, :app) do
      nil ->
        Mix.Project.config()[:app]

      app ->
        String.to_atom(app)
    end
  end
end
