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

    # The documented motivating case for `field_names`, and the only attribute
    # here that carries an override. `VerifyFieldNames` rejects a `_1` suffix
    # outright, so `address_line_1` cannot be generated without this mapping —
    # which makes it the one attribute that proves the override is honoured on
    # both sides rather than merely accepted by the DSL (#71).
    field_names(address_line_1: :addressLine1)
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

    attribute :address_line_1, :string do
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
      accept [:name, :email, :address_line_1]
    end

    # An Ash-level `get? true`, which `ConfigBuilder.get_action_context/3` reads
    # off the action itself. The `kotlin_rpc` DSL reaches the same branch through
    # its own `get?` and `get_by` options (#25), and the domain's `fetch_author`
    # covers that path; both need covering because they arrive from different
    # places.
    read :by_id do
      get? true

      argument :id, :uuid do
        allow_nil? false
      end

      filter expr(id == ^arg(:id))
    end

    # Keyset is the half of `AshPage` that offset never exercises: the cursors,
    # and `previousPage`/`nextPage`, which the server sends as `null` on an empty
    # page. Ash picks offset whenever both are allowed and the request carries no
    # cursor, so reaching keyset needs an action that allows nothing else.
    read :keyset_paged do
      pagination keyset?: true, offset?: false, required?: true, default_limit: 2
    end
  end
end
