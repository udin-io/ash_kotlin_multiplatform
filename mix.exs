# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.MixProject do
  use Mix.Project

  @version "0.1.3"

  @description """
  Generate type-safe Kotlin Multiplatform clients directly from your Ash resources and actions,
  ensuring end-to-end type safety between your backend and frontend.

  **Alpha Software** - This library is under active development. The API may change between versions.
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
      docs: docs(),
      description: @description,
      name: "AshKotlinMultiplatform",
      source_url: "https://github.com/udin-io/ash_kotlin_multiplatform",
      homepage_url: "https://github.com/udin-io/ash_kotlin_multiplatform",
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
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
      links: %{
        "GitHub" => "https://github.com/udin-io/ash_kotlin_multiplatform",
        "Discord" => "https://discord.gg/HTHRaaVPUc",
        "Website" => "https://ash-hq.org"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        {"README.md", title: "Home"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE", title: "License"}
      ],
      groups_for_modules: [
        "DSL Extensions": [
          AshKotlinMultiplatform.Resource,
          AshKotlinMultiplatform.Rpc
        ],
        "Code Generation": [
          AshKotlinMultiplatform.Rpc.Codegen,
          AshKotlinMultiplatform.Codegen.TypeMapper,
          AshKotlinMultiplatform.Codegen.TypeDiscovery,
          AshKotlinMultiplatform.Codegen.ResourceSchemas
        ],
        "RPC Pipeline": [
          AshKotlinMultiplatform.Rpc.Pipeline,
          AshKotlinMultiplatform.Rpc.Hooks
        ]
      ],
      before_closing_head_tag: fn _type ->
        """
        <style>
          .warning {
            background-color: #fff3cd;
            border: 1px solid #ffc107;
            border-radius: 4px;
            padding: 1rem;
            margin: 1rem 0;
          }
        </style>
        """
      end
    ]
  end

  defp deps do
    [
      {:ash_introspection, "~> 0.2.0"},
      {:ash, "~> 3.7"},
      {:ash_phoenix, "~> 2.0"},
      {:spark, "~> 2.0"},
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false}
    ]
  end
end
