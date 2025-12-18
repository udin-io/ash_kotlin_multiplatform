# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.TypeMapper do
  @moduledoc """
  Maps Ash types to Kotlin types.

  This module is responsible for converting Ash type definitions to their
  Kotlin equivalents, handling:
  - Primitive types (String, Int, Boolean, etc.)
  - Date/time types (using kotlinx-datetime or java.time)
  - Collection types (List<T>)
  - Nullable types (T?)
  - Custom type overrides
  """

  alias AshIntrospection.TypeSystem.Introspection

  @doc """
  Returns the Kotlin type for an Ash attribute.

  ## Parameters
  - `attribute` - An Ash attribute struct
  - `opts` - Options including :nullable (default: based on allow_nil?)

  ## Returns
  A string representing the Kotlin type.
  """
  def get_kotlin_type(attribute, opts \\ []) do
    nullable = Keyword.get(opts, :nullable, attribute.allow_nil?)
    type = attribute.type
    constraints = attribute.constraints || []

    kotlin_type = do_get_kotlin_type(type, constraints)

    if nullable do
      "#{kotlin_type}?"
    else
      kotlin_type
    end
  end

  @doc """
  Returns the Kotlin type for an Ash type and constraints.

  ## Parameters
  - `type` - The Ash type module or tuple
  - `constraints` - The type constraints

  ## Returns
  A string representing the Kotlin type.
  """
  def get_kotlin_type_for_type(type, constraints \\ []) do
    do_get_kotlin_type(type, constraints)
  end

  defp do_get_kotlin_type(type, constraints) do
    # Check for custom overrides first
    case find_override(type) do
      nil -> map_type(type, constraints)
      override -> override
    end
  end

  defp find_override(type) do
    overrides = AshKotlinMultiplatform.type_mapping_overrides()

    Enum.find_value(overrides, fn {ash_type, kotlin_type} ->
      if ash_type == type, do: kotlin_type
    end)
  end

  defp map_type({:array, inner_type}, constraints) do
    items_constraints = Keyword.get(constraints, :items, [])
    inner_kotlin_type = do_get_kotlin_type(inner_type, items_constraints)
    "List<#{inner_kotlin_type}>"
  end

  defp map_type(Ash.Type.String, _constraints), do: "String"
  defp map_type(Ash.Type.CiString, _constraints), do: "String"
  defp map_type(Ash.Type.Integer, _constraints), do: "Int"
  defp map_type(Ash.Type.Float, _constraints), do: "Double"
  defp map_type(Ash.Type.Boolean, _constraints), do: "Boolean"
  defp map_type(Ash.Type.Binary, _constraints), do: "ByteArray"

  # Decimal - use String for KMP compatibility
  defp map_type(Ash.Type.Decimal, _constraints), do: "String"

  # UUID types - use String for KMP compatibility
  defp map_type(Ash.Type.UUID, _constraints), do: "String"

  # Date/time types
  defp map_type(Ash.Type.Date, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.LocalDate"
      :java_time -> "java.time.LocalDate"
    end
  end

  defp map_type(Ash.Type.Time, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.LocalTime"
      :java_time -> "java.time.LocalTime"
    end
  end

  defp map_type(Ash.Type.UtcDatetime, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.Instant"
      :java_time -> "java.time.Instant"
    end
  end

  defp map_type(Ash.Type.UtcDatetimeUsec, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.Instant"
      :java_time -> "java.time.Instant"
    end
  end

  defp map_type(Ash.Type.DateTime, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.Instant"
      :java_time -> "java.time.ZonedDateTime"
    end
  end

  defp map_type(Ash.Type.NaiveDatetime, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.LocalDateTime"
      :java_time -> "java.time.LocalDateTime"
    end
  end

  # Atom type - check for :one_of constraint for enum
  defp map_type(Ash.Type.Atom, constraints) do
    case Keyword.get(constraints, :one_of) do
      nil -> "String"
      # For enums, we'll generate enum classes separately
      _values -> "String"
    end
  end

  # Map types
  defp map_type(Ash.Type.Map, constraints) do
    case Keyword.get(constraints, :fields) do
      nil -> AshKotlinMultiplatform.untyped_map_type()
      # For typed maps, we'll generate data classes separately
      _fields -> AshKotlinMultiplatform.untyped_map_type()
    end
  end

  defp map_type(Ash.Type.Keyword, _constraints) do
    AshKotlinMultiplatform.untyped_map_type()
  end

  # Tuple type
  defp map_type(Ash.Type.Tuple, constraints) do
    case Keyword.get(constraints, :fields) do
      nil -> "List<Any?>"
      _fields -> "List<Any?>"
    end
  end

  # Union type - will be handled as sealed class
  defp map_type(Ash.Type.Union, _constraints) do
    # Union types are generated as sealed classes separately
    "Any"
  end

  # Struct type
  defp map_type(Ash.Type.Struct, constraints) do
    case Keyword.get(constraints, :instance_of) do
      nil -> AshKotlinMultiplatform.untyped_map_type()
      module -> get_kotlin_class_name(module)
    end
  end

  # Check if it's an embedded resource
  defp map_type(type, constraints) when is_atom(type) do
    cond do
      Introspection.is_embedded_resource?(type) ->
        get_kotlin_class_name(type)

      # Check for NewType
      Ash.Type.NewType.new_type?(type) ->
        {unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(type, constraints, &has_interop_field_names?/1)

        do_get_kotlin_type(unwrapped_type, unwrapped_constraints)

      # Check if it's any Ash type
      Introspection.is_ash_type?(type) ->
        # Unknown Ash type, default to Any
        "Any"

      true ->
        # Module that might be a custom type
        "Any"
    end
  end

  # Fallback for non-atom types
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
  Gets the interop_field_names as a map, or empty map if not available.
  """
  def get_interop_field_names_map(nil), do: %{}

  def get_interop_field_names_map(module) when is_atom(module) do
    if Code.ensure_loaded?(module) && function_exported?(module, :interop_field_names, 0) do
      module.interop_field_names() |> Map.new()
    else
      %{}
    end
  end

  def get_interop_field_names_map(_), do: %{}

  @doc """
  Generates a Kotlin class name from an Elixir module.

  ## Examples

      iex> get_kotlin_class_name(MyApp.Accounts.User)
      "User"
  """
  def get_kotlin_class_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
  end

  @doc """
  Checks if an Ash type should be generated as a Kotlin enum class.
  """
  def is_enum_type?(type, constraints) do
    type == Ash.Type.Atom and Keyword.has_key?(constraints, :one_of)
  end

  @doc """
  Returns the enum values for an Ash.Type.Atom with :one_of constraint.
  """
  def get_enum_values(constraints) do
    Keyword.get(constraints, :one_of, [])
  end

  @doc """
  Checks if an Ash type should be generated as a Kotlin sealed class (union).
  """
  def is_union_type?(type) do
    type == Ash.Type.Union
  end

  @doc """
  Returns the union member types from constraints.
  """
  def get_union_types(type, constraints) do
    Introspection.get_union_types_from_constraints(type, constraints)
  end
end
