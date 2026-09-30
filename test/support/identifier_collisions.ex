# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

# Fixtures for #33's "Every way two identifiers collide" table. Live in
# test/support (compiled for every test run, not only when the test file
# that first needed them is targeted) because the mix task test
# (test/mix/tasks/ash_kotlin_multiplatform.codegen_test.exs) references
# ClashDomain too; a fixture defined inside one _test.exs file is only
# guaranteed to exist when THAT file is part of the run.

# Row 3 (an enum class vs a resource class), the simplest shape nothing
# else already catches: two resources typed the same (row 5) already fail
# `mix compile` through `VerifyUniqueTypeNames`, so that pairing would
# pass even with `Declarations.check/1` unwired and prove nothing. `Widget`
# names an enum `WidgetStatus` via its `:status` attribute; `ClashTwo` is
# typed `WidgetStatus` outright, a data class with no attribute-driven
# name to collide with. Named by no domain of their own; `ClashDomain`
# below publishes both.
defmodule AshKotlinMultiplatform.Test.IdentifierCollisions.ClashOne do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Widget")
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:on, :off]
      public? true
    end
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.IdentifierCollisions.ClashTwo do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  # Typed to match the resource-qualified name `Widget.status` now
  # generates (`WidgetStatus`, not `Status`) — the rename fixed the
  # original `Status`-vs-`Status` shape this fixture used to exercise.
  kotlin_multiplatform do
    type_name("WidgetStatus")
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.IdentifierCollisions.ClashDomain do
  @moduledoc false
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.IdentifierCollisions.ClashOne
    resource AshKotlinMultiplatform.Test.IdentifierCollisions.ClashTwo
  end

  kotlin_rpc do
    resource AshKotlinMultiplatform.Test.IdentifierCollisions.ClashOne do
      rpc_action :list_one, :read
    end

    resource AshKotlinMultiplatform.Test.IdentifierCollisions.ClashTwo do
      rpc_action :list_two, :read
    end
  end
end

# Rows 1 and 2: two resources each declaring a same-named attribute — an
# enum with different values, a union with different members. Before the
# resource-qualified rename, `Enum.uniq_by/2` silently kept one `Status`
# class (with one resource's values) and one `ContentUnion` class (with one
# resource's members); after it, each resource's own class survives under
# its own name.
defmodule AshKotlinMultiplatform.Test.IdentifierCollisions.Order do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Order")
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:pending, :shipped]
      public? true
    end

    attribute :content, :union do
      constraints types: [note: [type: :string]]

      public? true
    end
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.IdentifierCollisions.Payment do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Payment")
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:authorized, :captured, :refunded]
      public? true
    end

    attribute :content, :union do
      constraints types: [amount: [type: :integer]]

      public? true
    end
  end

  actions do
    defaults [:read]
  end
end

# Row 19: a resource typed after a name this generator's own static code
# references unqualified from a star import.
defmodule AshKotlinMultiplatform.Test.IdentifierCollisions.ReservedJson do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Json")
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.IdentifierCollisions.ReservedNameDomain do
  @moduledoc false
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.IdentifierCollisions.ReservedJson
  end

  kotlin_rpc do
    resource AshKotlinMultiplatform.Test.IdentifierCollisions.ReservedJson do
      rpc_action :list_reserved, :read
    end
  end
end
