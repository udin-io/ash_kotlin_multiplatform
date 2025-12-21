# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Resource.Info do
  @moduledoc """
  Introspection helpers for AshKotlinMultiplatform.Resource DSL.
  """

  use Spark.InfoGenerator,
    extension: AshKotlinMultiplatform.Resource,
    sections: [:kotlin_multiplatform]

  @doc """
  Returns the Kotlin Multiplatform type name for a resource.
  """
  def kotlin_multiplatform_type_name(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:kotlin_multiplatform], :type_name)
  end

  @doc """
  Returns the field name mappings for a resource.
  """
  def kotlin_multiplatform_field_names(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:kotlin_multiplatform], :field_names, [])
  end

  @doc """
  Returns the argument name mappings for a resource.
  """
  def kotlin_multiplatform_argument_names(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:kotlin_multiplatform], :argument_names, [])
  end

  @doc """
  Alias for kotlin_multiplatform_field_names/1 for compatibility with shared modules.
  """
  def kotlin_field_names(resource) do
    kotlin_multiplatform_field_names(resource)
  end

  @doc """
  Gets the original (internal) field name from a client field name.

  Looks up the field_names mapping and returns the internal field name
  if a mapping exists, otherwise returns nil.
  """
  def get_original_field_name(resource, client_field_name) do
    field_names = kotlin_multiplatform_field_names(resource)

    # Build reverse map: client_name -> internal_name
    Enum.find_value(field_names, fn {internal_name, client_name} ->
      if to_string(client_name) == to_string(client_field_name) do
        internal_name
      end
    end)
  end

  @doc """
  Checks if a resource is configured for Kotlin Multiplatform interop.
  """
  def is_kotlin_resource?(resource) do
    extensions = Spark.extensions(resource)
    AshKotlinMultiplatform.Resource in extensions
  rescue
    _ -> false
  end

  @doc """
  Checks if a resource has the AshKotlinMultiplatform.Resource extension.
  """
  def kotlin_multiplatform_resource?(resource) do
    extensions = Spark.extensions(resource)
    AshKotlinMultiplatform.Resource in extensions
  rescue
    _ -> false
  end

  @doc """
  Returns the Kotlin type name for a resource, falling back to the module name.
  """
  def kotlin_multiplatform_type_name!(resource) do
    case kotlin_multiplatform_type_name(resource) do
      nil ->
        resource
        |> Module.split()
        |> List.last()

      name ->
        name
    end
  end

  @doc """
  Returns the field name mappings for a resource (always returns a list).
  """
  def kotlin_multiplatform_field_names!(resource) do
    kotlin_multiplatform_field_names(resource) || []
  end

  @doc """
  Gets the mapped field name for a given field.

  Returns the mapped name if a mapping exists, otherwise returns the original field name.
  """
  def get_mapped_field_name(resource, field_name) do
    field_names = kotlin_multiplatform_field_names(resource)

    case Keyword.get(field_names, field_name) do
      nil -> field_name
      mapped -> mapped
    end
  end
end
