# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Todo do
  @moduledoc false
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name "Todo"
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
    end

    attribute :priority, :integer do
      default 0
    end

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
