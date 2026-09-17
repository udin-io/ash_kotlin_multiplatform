# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.SecretNote do
  @moduledoc """
  Embedded in `Secret`, a resource no `kotlin_rpc` block publishes and
  `Author.secrets` reaches.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :label, :string, public?: true
  end
end
