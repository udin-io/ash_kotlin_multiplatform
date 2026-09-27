# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.TypedQueriesTest do
  @moduledoc """
  `TypedQueries` has no dedicated test file before #63 — `typed_query` codegen
  was previously exercised only indirectly, through the manifest tests.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.TypedQueries
  alias AshKotlinMultiplatform.Test.ScopedDomain

  describe "generate_typed_query_type_and_const/4" do
    test "honors kotlin_fields_const_name for the fields object name" do
      [config] = AshKotlinMultiplatform.Rpc.Info.kotlin_rpc(ScopedDomain)
      [typed_query] = config.typed_queries
      action = Ash.Resource.Info.action(config.resource, typed_query.action)

      kotlin =
        TypedQueries.generate_typed_query_type_and_const(config.resource, action, typed_query, [
          config.resource
        ])

      assert kotlin =~ "object BOOK_TITLES_FIELDS {"
    end
  end
end
