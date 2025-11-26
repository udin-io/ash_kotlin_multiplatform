# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshKotlinMultiplatform.Codegen do
  @shortdoc "Generates Kotlin code from Ash resources"

  @moduledoc """
  Generates Kotlin code from Ash resources configured with AshKotlinMultiplatform extensions.

  ## Usage

      mix ash_kotlin_multiplatform.codegen

  ## Options

    * `--output` - Output file path (default: configured in :ash_kotlin_multiplatform, :output_file)
    * `--package` - Package name (default: configured in :ash_kotlin_multiplatform, :package_name)
    * `--app` - OTP app name (default: current mix project app)

  ## Examples

      # Generate with defaults
      mix ash_kotlin_multiplatform.codegen

      # Specify output file
      mix ash_kotlin_multiplatform.codegen --output lib/generated/AshRpc.kt

      # Specify package name
      mix ash_kotlin_multiplatform.codegen --package com.mycompany.myapp
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          package: :string,
          app: :string
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
        # Ensure directory exists
        output_file
        |> Path.dirname()
        |> File.mkdir_p!()

        # Write the file
        File.write!(output_file, kotlin_code)

        Mix.shell().info("Generated #{output_file}")
        :ok

      {:error, reason} ->
        Mix.shell().error("Code generation failed: #{reason}")
        exit({:shutdown, 1})
    end
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
