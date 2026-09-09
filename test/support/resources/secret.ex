# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Secret do
  @moduledoc """
  A plain Ash resource with no Kotlin extension, reachable from `Author.secrets`.

  It exists to prove the negative: nested field selection must refuse to walk
  from an exposed resource into one the Kotlin DSL never published, however
  public the relationship is on the Ash side.
  """
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string do
      public? true
    end
  end

  relationships do
    belongs_to :author, AshKotlinMultiplatform.Test.Author do
      public? true
      attribute_public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*]
  end
end
