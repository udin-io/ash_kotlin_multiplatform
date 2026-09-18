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

  # `PrivateMeta` is reached only through the `Author.first_private_meta`
  # aggregate, over an attribute `Book` keeps private. It needs ash 3.33.6 or
  # later: that is the release whose reachability walk follows an aggregate's
  # embedded type (ash-project/ash#2950), and `mix.exs` holds the floor there
  # (#100).
  test "lists every embedded resource in manifest.types, sorted by module" do
    assert Manifest.embedded_resources(Test.Manifest) == [
             Test.BookMeta,
             Test.Cover,
             Test.Edition,
             Test.PrivateMeta,
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
