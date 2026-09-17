# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.VaultSeal do
  @moduledoc """
  Embedded in `Vault`, which no `kotlin_rpc` block publishes and only the
  private `Event.vault` relationship reaches. It is the type that dropped out of
  the manifest on a rebuild before `BuildManifest` compiled every domain
  resource first (#84).
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, public?: true
  end
end
