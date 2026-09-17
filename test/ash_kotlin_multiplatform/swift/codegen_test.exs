# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Swift.CodegenTest do
  @moduledoc """
  The Swift generator declares the same embedded resources as the Kotlin one,
  because both read `Manifest.embedded_resources/1` (#84).
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Swift.Codegen

  setup_all do
    {:ok, swift} = Codegen.generate_swift_code(:ash_kotlin_multiplatform)
    %{swift: swift}
  end

  describe "embedded resource structs" do
    for {struct, route} <- [
          {"BookMeta", "an attribute of a published resource"},
          {"Edition", "another embedded resource"},
          {"UnionNote", "a union member"},
          {"SummaryOpts", "a generic action argument"},
          {"Summary", "a generic action return"},
          {"Cover", "a calculation"},
          {"SecretNote", "a relationship to an unpublished resource"},
          {"VaultSeal", "a private relationship"}
        ] do
      test "declares #{struct}, reached through #{route}", %{swift: swift} do
        assert swift =~ "struct #{unquote(struct)}: Codable"
      end
    end

    test "declares each embedded struct once", %{swift: swift} do
      assert length(Regex.scan(~r/struct BookMeta: Codable/, swift)) == 1
    end
  end
end
