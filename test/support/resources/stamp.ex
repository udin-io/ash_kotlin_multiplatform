# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Stamp do
  @moduledoc """
  An embedded resource whose `type_name` differs from its module name.

  The generated file declares `BookStamp`, so a field typed as this resource
  must name `BookStamp`, never `Stamp`.
  """
  use Ash.Resource, data_layer: :embedded, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("BookStamp")
  end

  attributes do
    attribute :label, :string, public?: true
  end
end
