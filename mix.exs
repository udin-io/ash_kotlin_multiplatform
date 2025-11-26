# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.MixProject do
  use Mix.Project

  @version "0.1.0"

  @description """
  Generate type-safe Kotlin Multiplatform clients directly from your Ash resources and actions,
  ensuring end-to-end type safety between your backend and frontend.
  """

  def project do
    [
      app: :ash_kotlin_multiplatform,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      deps: deps(),
      description: @description,
      source_url: "https://github.com/ash-project/ash_interop",
      homepage_url: "https://github.com/ash-project/ash_interop",
      consolidate_protocols: Mix.env() != :test
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      maintainers: [
        "Peter Shoukry"
      ],
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG* LICENSES),
      links: %{
        "GitHub" => "https://github.com/ash-project/ash_interop",
        "Discord" => "https://discord.gg/HTHRaaVPUc",
        "Website" => "https://ash-hq.org",
        "Forum" => "https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum"
      }
    ]
  end

  defp deps do
    [
      {:ash_introspection, path: "../ash_introspection"},
      {:ash, "~> 3.7"},
      {:ash_phoenix, "~> 2.0"},
      {:spark, "~> 2.0"},
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false}
    ]
  end
end
