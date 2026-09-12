# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.User do
  @moduledoc false
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name "User"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :email, :string do
      allow_nil? false
    end

    attribute :role, :atom do
      constraints one_of: [:admin, :user, :guest]
      default :user
    end

    attribute :active, :boolean do
      default true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :todos, AshKotlinMultiplatform.Test.Todo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :email, :role, :active]
    end

    update :update do
      primary? true
      accept [:name, :email, :role, :active]
    end
  end
end
