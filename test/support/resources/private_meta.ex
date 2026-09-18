# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.PrivateMeta do
  @moduledoc """
  Embedded in the private `Book.private_meta` attribute, reached only through
  the `Author.first_private_meta` aggregate. It is the fixture for the one
  route to an embedded type that runs through an aggregate. Ash's reachability
  walk follows that route since 3.33.6 (ash-project/ash#2950), so this type
  reaches `manifest.types` and both generators declare a class for it (#100).
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, public?: true
  end
end
