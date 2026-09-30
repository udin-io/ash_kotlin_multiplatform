# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

# Row 3 (an enum class vs a resource class), the simplest shape nothing
# else already catches: two resources typed the same (row 5) already fail
# `mix compile` through `VerifyUniqueTypeNames`, so that pairing would
# pass even with `Declarations.check/1` unwired and prove nothing. `Widget`
# names an enum `Status` via its `:status` attribute (unrenamed naming —
# the resource-qualified rename is a later commit); `ClashTwo` is typed
# `Status` outright, a data class with no attribute-driven name to collide
# with. Named by no domain of their own; `ClashDomain` below publishes both.
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

  kotlin_multiplatform do
    type_name("Status")
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

defmodule AshKotlinMultiplatform.Codegen.IdentifierCollisionsTest do
  @moduledoc """
  Every row of #33's "Every way two identifiers collide" table that reaches
  a full codegen pass, plus `Declarations.check/1`'s own unit coverage.

  `async: false`: several tests here swap `:ash_domains`, which is global,
  and the filter-type tests swap `:generate_filter_types`.
  """
  use ExUnit.Case, async: false

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

  describe "Declarations.check/1 is wired into generate_kotlin_code/2" do
    test "a real name clash stops codegen and names both sources" do
      result =
        with_ash_domains([Test.IdentifierCollisions.ClashDomain], fn ->
          Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
        end)

      assert {:error, message} = result
      assert message =~ "Status"
      assert message =~ "attribute :status on"
      assert message =~ "AshKotlinMultiplatform.Test.IdentifierCollisions.ClashOne"
      assert message =~ "AshKotlinMultiplatform.Test.IdentifierCollisions.ClashTwo"
    end
  end

  describe "guard — the repo's own test domain" do
    test "still generates {:ok, _}" do
      assert {:ok, _kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
    end
  end

  describe "declaration_fragments/2" do
    test "every fragment's text is exactly what the real generated file carries" do
      {:ok, kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
      fragments = Codegen.declaration_fragments(:ash_kotlin_multiplatform)

      assert fragments != []

      for {source, fragment} <- fragments do
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
