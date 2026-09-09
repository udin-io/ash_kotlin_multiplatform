# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Book do
  @moduledoc """
  The far side of `Author.books`, so a nested field request has somewhere to go.
  """
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshKotlinMultiplatform.Resource]

  ets do
    private? true
  end

  kotlin_multiplatform do
    type_name("Book")
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
      allow_nil? false
    end
  end

  relationships do
    belongs_to :author, AshKotlinMultiplatform.Test.Author do
      public? true
      attribute_public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:title, :author_id]
    end
  end
end
