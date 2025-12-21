# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.PaginationTypes do
  @moduledoc """
  Generates Kotlin pagination result types for RPC actions.

  Supports:
  - Offset pagination (limit/offset)
  - Keyset pagination (limit/after/before)
  - Mixed pagination (both offset and keyset)
  """

  alias AshIntrospection.Codegen.ActionIntrospection
  alias AshIntrospection.Helpers

  @doc """
  Generates the pagination result type based on the action's pagination support.

  ## Parameters

    * `resource` - The Ash resource
    * `action` - The Ash action
    * `rpc_action_name` - The name of the RPC action
    * `resource_name` - The Kotlin resource type name
    * `has_metadata` - Boolean indicating if metadata is enabled

  ## Returns

  A string containing the Kotlin result type definition for the appropriate pagination type.
  """
  def generate_pagination_result_type(
        _resource,
        action,
        rpc_action_name,
        resource_name,
        has_metadata
      ) do
    supports_offset = ActionIntrospection.action_supports_offset_pagination?(action)
    supports_keyset = ActionIntrospection.action_supports_keyset_pagination?(action)
    rpc_action_name_pascal = Helpers.snake_to_pascal_case(rpc_action_name)

    cond do
      supports_offset and supports_keyset ->
        generate_mixed_pagination_result_type(
          rpc_action_name_pascal,
          resource_name,
          has_metadata
        )

      supports_offset ->
        generate_offset_pagination_result_type(
          rpc_action_name_pascal,
          resource_name,
          has_metadata
        )

      supports_keyset ->
        generate_keyset_pagination_result_type(
          rpc_action_name_pascal,
          resource_name,
          has_metadata
        )

      true ->
        ""
    end
  end

  @doc """
  Generates an offset pagination result data class.

  The result includes:
  - results: List of items
  - hasMore: Boolean indicating if more results exist
  - limit: Number of items per page
  - offset: Current offset
  - count: Optional total count
  """
  def generate_offset_pagination_result_type(rpc_action_name_pascal, resource_name, _has_metadata) do
    """
    @Serializable
    data class #{rpc_action_name_pascal}OffsetResult(
        val results: List<#{resource_name}>,
        val hasMore: Boolean,
        val limit: Int,
        val offset: Int,
        val count: Int? = null
    )
    """
  end

  @doc """
  Generates a keyset pagination result data class.

  The result includes:
  - results: List of items
  - hasMore: Boolean indicating if more results exist
  - limit: Number of items per page
  - after: Cursor for next page (or null)
  - before: Cursor for previous page (or null)
  - previousPage: Cursor string for previous page
  - nextPage: Cursor string for next page
  - count: Optional total count
  """
  def generate_keyset_pagination_result_type(rpc_action_name_pascal, resource_name, _has_metadata) do
    """
    @Serializable
    data class #{rpc_action_name_pascal}KeysetResult(
        val results: List<#{resource_name}>,
        val hasMore: Boolean,
        val limit: Int,
        @SerialName("after")
        val afterCursor: String? = null,
        @SerialName("before")
        val beforeCursor: String? = null,
        val previousPage: String = "",
        val nextPage: String = "",
        val count: Int? = null
    )
    """
  end

  @doc """
  Generates a mixed pagination sealed class (supports both offset and keyset).

  Uses sealed class hierarchy to discriminate between offset and keyset results.
  """
  def generate_mixed_pagination_result_type(rpc_action_name_pascal, resource_name, _has_metadata) do
    """
    @Serializable
    sealed class #{rpc_action_name_pascal}PaginatedResult {
        abstract val results: List<#{resource_name}>
        abstract val hasMore: Boolean
        abstract val limit: Int
        abstract val count: Int?
    }

    @Serializable
    @SerialName("offset")
    data class #{rpc_action_name_pascal}OffsetPaginatedResult(
        override val results: List<#{resource_name}>,
        override val hasMore: Boolean,
        override val limit: Int,
        override val count: Int? = null,
        val offset: Int
    ) : #{rpc_action_name_pascal}PaginatedResult()

    @Serializable
    @SerialName("keyset")
    data class #{rpc_action_name_pascal}KeysetPaginatedResult(
        override val results: List<#{resource_name}>,
        override val hasMore: Boolean,
        override val limit: Int,
        override val count: Int? = null,
        @SerialName("after")
        val afterCursor: String? = null,
        @SerialName("before")
        val beforeCursor: String? = null,
        val previousPage: String = "",
        val nextPage: String = ""
    ) : #{rpc_action_name_pascal}PaginatedResult()
    """
  end

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
