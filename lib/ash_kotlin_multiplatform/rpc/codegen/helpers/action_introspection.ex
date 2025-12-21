# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.Helpers.ActionIntrospection do
  @moduledoc """
  Introspection helpers for Ash actions used in Kotlin code generation.

  This module provides functions to analyze action characteristics such as
  pagination support, input requirements, and return types.
  """

  alias AshIntrospection.Codegen.ActionIntrospection, as: SharedIntrospection

  # Delegate to shared introspection module from ash_introspection

  @doc """
  Checks if an action supports any form of pagination.
  """
  defdelegate action_supports_pagination?(action), to: SharedIntrospection

  @doc """
  Checks if an action supports offset pagination (limit/offset).
  """
  defdelegate action_supports_offset_pagination?(action), to: SharedIntrospection

  @doc """
  Checks if an action supports keyset pagination (before/after cursors).
  """
  defdelegate action_supports_keyset_pagination?(action), to: SharedIntrospection

  @doc """
  Checks if pagination is required for the action (not optional).
  """
  defdelegate action_requires_pagination?(action), to: SharedIntrospection

  @doc """
  Checks if the action supports counting results.
  """
  defdelegate action_supports_countable?(action), to: SharedIntrospection

  @doc """
  Determines the input type for an action.
  Returns :required, :optional, or :none.
  """
  defdelegate action_input_type(resource, action), to: SharedIntrospection

  @doc """
  Gets the list of required input fields for an action.
  """
  defdelegate get_required_inputs(resource, action), to: SharedIntrospection

  @doc """
  Gets the list of optional input fields for an action.
  """
  defdelegate get_optional_inputs(resource, action), to: SharedIntrospection

  @doc """
  Checks if an action returns a field-selectable type.
  Returns {:ok, type, value} or {:error, reason}.
  """
  defdelegate action_returns_field_selectable_type?(action), to: SharedIntrospection

  @doc """
  Checks if an action has a default limit set for pagination.
  """
  def action_has_default_limit?(action) do
    case action.pagination do
      nil -> false
      %{default_limit: limit} when is_integer(limit) and limit > 0 -> true
      _ -> false
    end
  end
end
