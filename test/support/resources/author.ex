# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Author do
  @moduledoc """
  A resource whose fields are public and whose data is real, for field selection.

  The other test resources keep their attributes private and have no data layer,
  so they cannot answer a nested request at all. Field selection needs a public
  relationship to walk into, a public calculation and a public aggregate to
  prove non-attribute fields are reachable, and stored rows to read back — hence
  the ETS data layer, private so concurrent tests cannot see each other's rows.
  """
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshKotlinMultiplatform.Resource]

  ets do
    private? true
  end

  kotlin_multiplatform do
    type_name("Author")
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      public? true
      allow_nil? false
    end

    attribute :email, :string do
      public? true
    end
  end

  relationships do
    has_many :books, AshKotlinMultiplatform.Test.Book do
      public? true
    end

    # Deliberately not exposed to the Kotlin client: a nested request must not be
    # able to walk into a resource the DSL never published.
    has_many :secrets, AshKotlinMultiplatform.Test.Secret do
      public? true
    end
  end

  calculations do
    calculate :display_name, :string, expr(name <> " <" <> email <> ">") do
      public? true
    end
  end

  aggregates do
    count :book_count, :books do
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :email]
    end
  end
end
