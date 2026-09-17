# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.PrivateMeta do
  @moduledoc """
  Embedded in the private `Book.private_meta` attribute, reached only through
  the `Author.first_private_meta` aggregate. A `first` aggregate's `type` is
  `nil` when the manifest is built, so Ash's reachability misses this type and
  no generated class declares it. The upstream gap is out of scope for #84.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, public?: true
  end
end
