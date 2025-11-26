# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Resource.Info do
  @moduledoc """
  Introspection helpers for AshKotlinMultiplatform.Resource DSL.
  """

  use Spark.InfoGenerator, extension: AshKotlinMultiplatform.Resource, sections: [:kotlin]

  @doc """
  Returns the Kotlin type name for a resource.
  """
  def kotlin_type_name(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:kotlin], :type_name)
  end

  @doc """
  Returns the field name mappings for a resource.
  """
  def kotlin_field_names(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:kotlin], :field_names, [])
  end

  @doc """
  Returns the argument name mappings for a resource.
  """
  def kotlin_argument_names(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:kotlin], :argument_names, [])
  end
end
