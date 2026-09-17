# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Summary do
  @moduledoc """
  Reached only as the return type of the generic `Book.summarize` action.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, public?: true
  end
end
