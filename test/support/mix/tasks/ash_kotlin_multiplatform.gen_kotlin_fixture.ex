# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshKotlinMultiplatform.GenKotlinFixture do
  @shortdoc "Generates the Kotlin sources compiled by the CI compile gate"

  @moduledoc """
  Writes the generated Kotlin for the library's own test resources into the
  Gradle fixture at `test/fixtures/kotlin_compile`, so a real Kotlin compiler
  can be run against it.

  Every "generated code does not compile" defect filed against this library so
  far (#20, #23, #24, #30, #33) was found by a human reading emitted strings.
  This task exists to hand those strings to `kotlinc` instead.

  One Gradle subproject is written per `:datetime_library` setting. The two
  settings emit different imports, different field types and a different
  `Instant` serializer, so compiling only the default would leave half the
  date/time code unchecked. They must be separate subprojects rather than two
  files in one: both declare the same package and the same top-level names, so
  Kotlin rejects them as redeclarations if compiled together.

  This task lives in `test/support` on purpose. It is a development gate, not
  part of the published package, and `mix.exs` ships `lib` only.

  ## Usage

      MIX_ENV=test mix ash_kotlin_multiplatform.gen_kotlin_fixture
  """

  use Mix.Task

  @fixture_root "test/fixtures/kotlin_compile"

  @variants [
    {:kotlinx_datetime, "kotlinx-datetime"},
    {:java_time, "java-time"}
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    original = Application.get_env(:ash_kotlin_multiplatform, :datetime_library)

    try do
      Enum.each(@variants, &generate_variant/1)
    after
      restore_datetime_library(original)
    end
  end

  defp generate_variant({datetime_library, subproject}) do
    Application.put_env(:ash_kotlin_multiplatform, :datetime_library, datetime_library)

    output = Path.join([@fixture_root, subproject, "src/main/kotlin/AshRpc.kt"])

    case AshKotlinMultiplatform.Rpc.Codegen.generate_kotlin_code(:ash_kotlin_multiplatform, []) do
      {:ok, kotlin_code} ->
        output |> Path.dirname() |> File.mkdir_p!()
        File.write!(output, kotlin_code)
        Mix.shell().info("Generated #{output} (datetime_library: #{inspect(datetime_library)})")

      {:error, reason} ->
        Mix.shell().error("Code generation failed for #{inspect(datetime_library)}: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp restore_datetime_library(nil),
    do: Application.delete_env(:ash_kotlin_multiplatform, :datetime_library)

  defp restore_datetime_library(value),
    do: Application.put_env(:ash_kotlin_multiplatform, :datetime_library, value)
end
