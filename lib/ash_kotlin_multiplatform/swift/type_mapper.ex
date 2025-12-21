# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Swift.TypeMapper do
  @moduledoc """
  Maps Ash types to Swift types.

  This module is responsible for converting Ash type definitions to their
  Swift equivalents, handling:
  - Primitive types (String, Int, Bool, etc.)
  - Date/time types (using Foundation Date or ISO8601 strings)
  - Collection types ([T])
  - Optional types (T?)
  - Custom type overrides
  """

  alias AshIntrospection.TypeSystem.Introspection

  @doc """
  Returns the Swift type for an Ash attribute.

  ## Parameters
  - `attribute` - An Ash attribute struct
  - `opts` - Options including :nullable (default: based on allow_nil?)

  ## Returns
  A string representing the Swift type.
  """
  def get_swift_type(attribute, opts \\ []) do
    nullable = Keyword.get(opts, :nullable, attribute.allow_nil?)
    type = attribute.type
    constraints = attribute.constraints || []

    swift_type = do_get_swift_type(type, constraints)

    if nullable do
      "#{swift_type}?"
    else
      swift_type
    end
  end

  @doc """
  Returns the Swift type for an Ash type and constraints.

  ## Parameters
  - `type` - The Ash type module or tuple
  - `constraints` - The type constraints

  ## Returns
  A string representing the Swift type.
  """
  def get_swift_type_for_type(type, constraints \\ []) do
    do_get_swift_type(type, constraints)
  end

  defp do_get_swift_type(type, constraints) do
    # Check for custom overrides first
    case find_override(type) do
      nil -> map_type(type, constraints)
      override -> override
    end
  end

  defp find_override(type) do
    overrides = Application.get_env(:ash_kotlin_multiplatform, :swift_type_mapping_overrides, [])

    Enum.find_value(overrides, fn {ash_type, swift_type} ->
      if ash_type == type, do: swift_type
    end)
  end

  defp map_type({:array, inner_type}, constraints) do
    items_constraints = Keyword.get(constraints, :items, [])
    inner_swift_type = do_get_swift_type(inner_type, items_constraints)
    "[#{inner_swift_type}]"
  end

  defp map_type(Ash.Type.String, _constraints), do: "String"
  defp map_type(Ash.Type.CiString, _constraints), do: "String"
  defp map_type(Ash.Type.Integer, _constraints), do: "Int"
  defp map_type(Ash.Type.Float, _constraints), do: "Double"
  defp map_type(Ash.Type.Boolean, _constraints), do: "Bool"
  defp map_type(Ash.Type.Binary, _constraints), do: "Data"

  # Decimal - use String for compatibility (or Decimal library if available)
  defp map_type(Ash.Type.Decimal, _constraints), do: "String"

  # UUID types - use String (or UUID if needed)
  defp map_type(Ash.Type.UUID, _constraints), do: "String"

  # Date/time types - use ISO8601 strings for JSON compatibility
  defp map_type(Ash.Type.Date, _constraints), do: "String"
  defp map_type(Ash.Type.Time, _constraints), do: "String"
  defp map_type(Ash.Type.UtcDatetime, _constraints), do: "String"
  defp map_type(Ash.Type.UtcDatetimeUsec, _constraints), do: "String"
  defp map_type(Ash.Type.DateTime, _constraints), do: "String"
  defp map_type(Ash.Type.NaiveDatetime, _constraints), do: "String"

  # Atom type - check for :one_of constraint for enum
  defp map_type(Ash.Type.Atom, constraints) do
    case Keyword.get(constraints, :one_of) do
      nil -> "String"
      _values -> "String"
    end
  end

  # Map types
  defp map_type(Ash.Type.Map, constraints) do
    case Keyword.get(constraints, :fields) do
      nil -> "[String: Any]"
      _fields -> "[String: Any]"
    end
  end

  defp map_type(Ash.Type.Keyword, _constraints), do: "[String: Any]"

  # Tuple type
  defp map_type(Ash.Type.Tuple, _constraints), do: "[Any]"

  # Union type - will be handled separately as enum with associated values
  defp map_type(Ash.Type.Union, _constraints), do: "Any"

  # Struct type
  defp map_type(Ash.Type.Struct, constraints) do
    case Keyword.get(constraints, :instance_of) do
      nil -> "[String: Any]"
      module -> get_swift_class_name(module)
    end
  end

  # Check if it's an embedded resource
  defp map_type(type, constraints) when is_atom(type) do
    cond do
      Introspection.is_embedded_resource?(type) ->
        get_swift_class_name(type)

      Ash.Type.NewType.new_type?(type) ->
        {unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(type, constraints, &has_interop_field_names?/1)

        do_get_swift_type(unwrapped_type, unwrapped_constraints)

      Introspection.is_ash_type?(type) ->
        "Any"

      true ->
        "Any"
    end
  end

  defp map_type(_, _constraints), do: "Any"

  @doc """
  Checks if a module has interop_field_names/0 callback.
  """
  def has_interop_field_names?(nil), do: false

  def has_interop_field_names?(module) when is_atom(module) do
    Code.ensure_loaded?(module) && function_exported?(module, :interop_field_names, 0)
  end

  def has_interop_field_names?(_), do: false

  @doc """
  Generates a Swift class name from an Elixir module.
  """
  def get_swift_class_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
  end
end
