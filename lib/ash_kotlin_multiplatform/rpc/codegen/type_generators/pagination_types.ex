# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.PaginationTypes do
  @moduledoc """
  Pagination helpers for RPC code generation.
  """

  alias AshIntrospection.Codegen.ActionIntrospection

  @doc """
  Generates pagination config types for request configuration.
  """
  def generate_pagination_config_types do
    """
    // Pagination config types
    @Serializable
    data class OffsetPaginationConfig(
        val limit: Int? = null,
        val offset: Int? = null,
        val count: Boolean = false
    )

    @Serializable
    data class KeysetPaginationConfig(
        val limit: Int? = null,
        val after: String? = null,
        val before: String? = null,
        val count: Boolean = false
    )
    """
  end

  @doc """
  Checks if an action supports any form of pagination.
  """
  def action_supports_pagination?(action) do
    ActionIntrospection.action_supports_pagination?(action)
  end

  @doc """
  Checks if an action requires pagination (not optional).
  """
  def action_requires_pagination?(action) do
    ActionIntrospection.action_requires_pagination?(action)
  end
end
