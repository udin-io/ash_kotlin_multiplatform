# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Event do
  @moduledoc """
  Public date/time attributes in every shape the Kotlin generator has to serialize.

  The other test resources leave their attributes private, so they exercise no
  field generation at all — `Ash.Resource.Info.public_attributes/1` returns only
  the primary key.
  """
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Event")
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      public? true
      allow_nil? false
    end

    attribute :starts_on, :date, public?: true
    attribute :occurred_at, :utc_datetime, public?: true
    attribute :recorded_at, :utc_datetime_usec, public?: true
    attribute :reminder_ats, {:array, :utc_datetime}, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :starts_on, :occurred_at, :reminder_ats]
    end

    # Exercises the metadata path: the Config class needs a metadataFields property
    # for every action whose function body reads config.metadataFields.
    create :register do
      accept [:name]
      metadata :registered_at, :utc_datetime
    end
  end
end
