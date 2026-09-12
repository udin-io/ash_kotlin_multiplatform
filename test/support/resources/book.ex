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

    # Private on purpose. `Ash.Info.Manifest.Generator.generate/1` defaults
    # `:include_private_relationships?` to false, so this relationship is in no
    # manifest built with the defaults — which is how `ash_introspection`
    # shipped a `relationship/3` that answered nil where `Ash.Resource.Info`
    # answers the relationship. This is the fixture that fails if
    # `BuildManifest` ever stops passing the option.
    belongs_to :editor, AshKotlinMultiplatform.Test.Author do
      public? false
      attribute_public? false
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
