# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Edition do
  @moduledoc """
  Reached only through `BookMeta.edition`, one embedded level down. The old
  walk named `Edition` in `BookMeta` and never declared it (#84).
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :number, :integer, public?: true
  end
end
