# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

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

defmodule AshKotlinMultiplatform.Codegen.IdentifierCollisionsTest do
  @moduledoc """
  Every row of #33's "Every way two identifiers collide" table that reaches
  a full codegen pass, plus `Declarations.check/1`'s own unit coverage.

  `async: false`: several tests here swap `:ash_domains`, which is global,
  and the filter-type tests swap `:generate_filter_types`.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Rpc.Codegen
  alias AshKotlinMultiplatform.Test

  defp with_ash_domains(domains, fun) do
    previous = Application.get_env(:ash_kotlin_multiplatform, :ash_domains)
    Application.put_env(:ash_kotlin_multiplatform, :ash_domains, domains)

    try do
      fun.()
    after
      case previous do
        nil -> Application.delete_env(:ash_kotlin_multiplatform, :ash_domains)
        value -> Application.put_env(:ash_kotlin_multiplatform, :ash_domains, value)
      end
    end
  end

  defp generated_file(domains) do
    with_ash_domains(domains, fn ->
      {:ok, code} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
      code
    end)
  end

  describe "row 16 — a resource in two domains' kotlin_rpc blocks" do
    test "the object wrapper carries every domain's actions" do
      kotlin = generated_file([Test.Domain, Test.ScopedDomain])

      assert kotlin =~ "fun list(client: HttpClient, config: ListBooksConfig)"

      assert kotlin =~
               "fun scopedListBooks(client: HttpClient, config: ScopedListBooksConfig)"
    end

    test "still exactly one BookRpc object" do
      kotlin = generated_file([Test.Domain, Test.ScopedDomain])

      assert length(Regex.scan(~r/^object BookRpc /m, kotlin)) == 1
    end
  end

  describe "row 1 — two same-named enum attributes, different values, two resources" do
    test "both classes are emitted with their own values, each field names its own" do
      {data_classes, _embedded, enum_classes, _sealed} =
        ResourceSchemas.generate_all_schemas(
          [Test.IdentifierCollisions.Order, Test.IdentifierCollisions.Payment],
          []
        )

      assert data_classes =~ "val status: OrderStatus? = null"
      assert data_classes =~ "val status: PaymentStatus? = null"

      assert enum_classes =~ "enum class OrderStatus {"
      assert enum_classes =~ "@SerialName(\"pending\") PENDING"
      assert enum_classes =~ "@SerialName(\"shipped\") SHIPPED"

      assert enum_classes =~ "enum class PaymentStatus {"
      assert enum_classes =~ "@SerialName(\"authorized\") AUTHORIZED"
      assert enum_classes =~ "@SerialName(\"captured\") CAPTURED"
      assert enum_classes =~ "@SerialName(\"refunded\") REFUNDED"

      refute enum_classes =~ "enum class Status {"
    end
  end

  describe "row 2 — two same-named union attributes, two resources" do
    test "each union class is named after its own resource" do
      {data_classes, _embedded, _enum, sealed_classes} =
        ResourceSchemas.generate_all_schemas(
          [Test.IdentifierCollisions.Order, Test.IdentifierCollisions.Payment],
          []
        )

      assert data_classes =~ "val content: OrderContentUnion? = null"
      assert data_classes =~ "val content: PaymentContentUnion? = null"

      assert sealed_classes =~ "sealed class OrderContentUnion {"
      assert sealed_classes =~ "sealed class PaymentContentUnion {"
      refute sealed_classes =~ "sealed class ContentUnion {"
    end
  end

  describe "guard — two resources with identical enum values still generate {:ok, _}" do
    test "identical value sets on differently-named classes do not clash" do
      {_data, _embedded, enum_classes, _sealed} =
        ResourceSchemas.generate_all_schemas(
          [Test.IdentifierCollisions.Order, Test.IdentifierCollisions.Payment],
          []
        )

      fragments = [
        {"attribute :status on Order", "enum class OrderStatus { PENDING }"},
        {"attribute :status on Payment", "enum class PaymentStatus { PENDING }"}
      ]

      assert AshKotlinMultiplatform.Codegen.Declarations.check(fragments) == :ok
      assert enum_classes =~ "OrderStatus"
      assert enum_classes =~ "PaymentStatus"
    end
  end

  describe "Declarations.check/1 is wired into generate_kotlin_code/2" do
    test "a real name clash stops codegen and names both sources" do
      result =
        with_ash_domains([Test.IdentifierCollisions.ClashDomain], fn ->
          Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
        end)

      assert {:error, message} = result
      assert message =~ "WidgetStatus"
      assert message =~ "attribute :status on"
      assert message =~ "AshKotlinMultiplatform.Test.IdentifierCollisions.ClashOne"
      assert message =~ "AshKotlinMultiplatform.Test.IdentifierCollisions.ClashTwo"
    end
  end

  describe "row 19 — a resource shadowing a star-imported name" do
    test "a resource typed Json stops codegen, naming the star import it shadows" do
      result =
        with_ash_domains([Test.IdentifierCollisions.ReservedNameDomain], fn ->
          Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
        end)

      assert {:error, message} = result
      assert message =~ "Json"
      assert message =~ "star import kotlinx.serialization.json"
      assert message =~ "AshKotlinMultiplatform.Test.IdentifierCollisions.ReservedJson"
    end
  end

  describe "guard — the repo's own test domain" do
    test "still generates {:ok, _}" do
      assert {:ok, _kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
    end
  end

  describe "declaration_fragments/2" do
    test "every real fragment's text is exactly what the real generated file carries" do
      {:ok, kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
      fragments = Codegen.declaration_fragments(:ash_kotlin_multiplatform)

      assert fragments != []

      # Reserved-name guards (row 19) are the one deliberate exception: a
      # sentinel "class Json" fragment does not itself appear anywhere in
      # the real file — the whole point is to catch a REAL declaration
      # that would collide with it. Every other fragment IS real output.
      for {source, fragment} <- fragments, not (source =~ "star import") do
        assert kotlin =~ String.trim(fragment),
               "#{source} produced a fragment the real generated file does not carry verbatim"
      end
    end

    test "carries a source for a known rpc_action, resource, filter type and object wrapper" do
      fragments = Codegen.declaration_fragments(:ash_kotlin_multiplatform, with_filters: true)
      sources = Enum.map(fragments, &elem(&1, 0))

      assert "rpc_action :list_books on AshKotlinMultiplatform.Test.Book" in sources
      assert "resource AshKotlinMultiplatform.Test.Book (data class)" in sources
      assert "resource AshKotlinMultiplatform.Test.Book (filter type)" in sources
      assert "object wrapper for AshKotlinMultiplatform.Test.Book" in sources
    end
  end
end
