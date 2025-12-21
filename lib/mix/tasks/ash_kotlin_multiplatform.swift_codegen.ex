# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshKotlinMultiplatform.SwiftCodegen do
  @shortdoc "Generates Swift code from Ash resources"

  @moduledoc """
  Generates Swift code from Ash resources configured with AshKotlinMultiplatform extensions.

  ## Usage

      mix ash_kotlin_multiplatform.swift_codegen

  ## Options

    * `--output` - Output file path (default: "ios/Generated/AshRpc.swift")
    * `--base-url` - Base URL for the API (default: "http://localhost:4000")
    * `--app` - OTP app name (default: current mix project app)

  ## Examples

      # Generate with defaults
      mix ash_kotlin_multiplatform.swift_codegen

      # Specify output file
      mix ash_kotlin_multiplatform.swift_codegen --output Sources/Generated/AshRpc.swift

      # Specify base URL for production
      mix ash_kotlin_multiplatform.swift_codegen --base-url https://api.example.com
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          base_url: :string,
          app: :string
        ],
        aliases: [
          o: :output,
          u: :base_url
        ]
      )

    otp_app = get_otp_app(opts)
    output_file = Keyword.get(opts, :output, swift_output_file())
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")

    codegen_opts = [base_url: base_url]

    Mix.shell().info("Generating Swift code for #{otp_app}...")

    case AshKotlinMultiplatform.Swift.Codegen.generate_swift_code(otp_app, codegen_opts) do
      {:ok, swift_code} ->
        # Ensure directory exists
        output_file
        |> Path.dirname()
        |> File.mkdir_p!()

        # Write the file
        File.write!(output_file, swift_code)

        Mix.shell().info("Generated #{output_file}")
        :ok

      {:error, reason} ->
        Mix.shell().error("Swift code generation failed: #{reason}")
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

  defp swift_output_file do
    Application.get_env(
      :ash_kotlin_multiplatform,
      :swift_output_file,
      "ios/Generated/AshRpc.swift"
    )
  end
end
