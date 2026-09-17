# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.BookMeta do
  @moduledoc """
  Embedded in `Book.meta`, a public attribute of a published resource: the
  one route the old one-level attribute walk found.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :isbn, :string, public?: true
    attribute :edition, AshKotlinMultiplatform.Test.Edition, public?: true
  end
end
