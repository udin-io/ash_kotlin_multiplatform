# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.EmbeddedResourcesTest do
  @moduledoc """
  `Manifest.embedded_resources/1`, the one list of embedded resources both code
  generators read (#84).
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Test

  test "lists every embedded resource in manifest.types, sorted by module" do
    assert Manifest.embedded_resources(Test.Manifest) == [
             Test.BookMeta,
             Test.Cover,
             Test.Edition,
             Test.SecretNote,
             Test.Summary,
             Test.SummaryOpts,
             Test.UnionNote,
             Test.VaultSeal
           ]
  end

  test "defaults to the manifest named in config" do
    assert Manifest.embedded_resources() == Manifest.embedded_resources(Test.Manifest)
  end
end
