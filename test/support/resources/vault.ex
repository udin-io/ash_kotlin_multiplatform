# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Vault do
  @moduledoc """
  A domain resource no `kotlin_rpc` block names, reached only through the
  private `Event.vault` relationship.

  `VaultSeal` is embedded here and nowhere else, so it reaches the manifest only
  if `BuildManifest` compiles this module before Ash's reachability walk runs.
  """
  use Ash.Resource, domain: AshKotlinMultiplatform.Test.Domain

  attributes do
    uuid_primary_key :id
    attribute :seal, AshKotlinMultiplatform.Test.VaultSeal, public?: true
  end

  actions do
    defaults [:read]
  end
end
