# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Todo do
  @moduledoc """
  Carries the attribute types that have no direct Kotlin equivalent.

  `Ash.Type.Map`, `Ash.Type.Keyword`, `Ash.Type.Tuple`, `Ash.Type.Union` and any
  Ash type the mapper does not recognise all reach Kotlin as `Any`, which
  kotlinx-serialization refuses inside a `@Serializable` class ("Serializer has
  not been found for type 'Any'"). `:status` is public for the matching reason on
  the other side: an `:atom` with `one_of` has an enum class generated for it, so
  the field has to name that class rather than `String`.

  Only `Ash.Resource.Info.public_attributes/1` reaches the generator, hence
  `public? true` on every attribute that is here to be generated.
  """
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Todo")
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
    end

    attribute :description, :string

    attribute :status, :atom do
      constraints one_of: [:pending, :in_progress, :completed]
      default :pending
      public? true
    end

    attribute :priority, :integer do
      default 0
    end

    attribute :metadata, :map, public?: true

    attribute :settings, :keyword do
      constraints fields: [notify: [type: :boolean]]
      public? true
    end

    attribute :position, :tuple do
      constraints fields: [x: [type: :integer], y: [type: :integer]]
      public? true
    end

    attribute :content, :union do
      constraints types: [
                    text: [type: :string],
                    note: [type: :map, constraints: [fields: [body: [type: :string]]]],
                    blob: [type: :map]
                  ]

      public? true
    end

    # Ash.Type.Term is a real Ash type the mapper has no case for, so it takes the
    # unknown-type fallback rather than any of the branches above.
    attribute :scratch, Ash.Type.Term, public?: true

    attribute :due_date, :date

    attribute :completed_at, :utc_datetime

    attribute :tags, {:array, :string} do
      default []
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, AshKotlinMultiplatform.Test.User
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:title, :description, :status, :priority, :due_date, :tags, :user_id]
    end

    update :update do
      primary? true
      accept [:title, :description, :status, :priority, :due_date, :completed_at, :tags]
    end

    read :by_status do
      argument :status, :atom do
        constraints one_of: [:pending, :in_progress, :completed]
        allow_nil? false
      end

      filter expr(status == ^arg(:status))
    end
  end
end
