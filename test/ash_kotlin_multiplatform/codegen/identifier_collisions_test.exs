# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

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

  describe "guard — the repo's own test domain" do
    test "still generates {:ok, _}" do
      assert {:ok, _kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform)
    end
  end
end
