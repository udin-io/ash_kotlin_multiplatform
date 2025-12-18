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
end
