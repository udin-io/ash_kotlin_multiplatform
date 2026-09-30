# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.KotlinStaticTest do
  @moduledoc """
  `reserved_top_level_names/1` (#33 row 19, owner decision 2026-09-30): a
  generated top-level class shadowing a star-imported name this library
  itself references unqualified breaks the consumer's Kotlin build — not
  a theoretical risk, verified for real with `gradle compileKotlin` (see
  the PR body). Every name here was confirmed present, bare (never
  qualified with its package), in the real generated fixture before being
  added — not guessed from the package's public API.

  Returns `{source, fragment}` pairs, the same shape every other section
  hands `Codegen.Declarations.check/1`, so a reserved name is just one
  more source in that list rather than a second check with its own rules.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.Declarations
  alias AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic

  defp names,
    do:
      KotlinStatic.reserved_top_level_names([]) |> Enum.flat_map(&Declarations.names(elem(&1, 1)))

  describe "reserved_top_level_names/1" do
    test "carries the kotlinx.serialization annotations every declaration uses bare" do
      assert "Serializable" in names()
      assert "SerialName" in names()
      assert "Contextual" in names()
    end

    test "carries Json, used bare for the shared serializer" do
      assert "Json" in names()
    end

    test "carries HttpClient, used bare by the HTTP client factory" do
      assert "HttpClient" in names()
    end

    test "carries ContentType and ContentNegotiation, used bare in every rpc function" do
      assert "ContentType" in names()
      assert "ContentNegotiation" in names()
    end

    test "does not reserve Instant — nothing in the generated file uses it bare" do
      # Every datetime reference the generator emits is fully qualified
      # (`kotlinx.datetime.Instant`, `java.time.Instant`), under both
      # :datetime_library settings, so a resource typed `Instant` does not
      # shadow anything real. Flagged on the PR: the owner named `Instant`
      # alongside `Json`/`HttpClient` as an example before this was
      # checked for real.
      refute "Instant" in names()
    end

    test "each pair's fragment declares exactly the name its source names" do
      for {source, fragment} <- KotlinStatic.reserved_top_level_names([]) do
        [name] = Declarations.names(fragment)
        assert source =~ name
      end
    end

    test "carries a source naming the star import it guards" do
      sources = KotlinStatic.reserved_top_level_names([]) |> Enum.map(&elem(&1, 0))

      assert Enum.any?(sources, &(&1 =~ "kotlinx.serialization.json"))
      assert Enum.any?(sources, &(&1 =~ "io.ktor.client"))
    end
  end
end
