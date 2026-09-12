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
  Resolves a client field name to the internal field name.

  A string is looked up against the `field_names` mapping and answers the
  internal name, or `nil` when the resource declares no such override.

  An atom passes through unchanged, because an atom is already an internal
  name. That is the contract
  `AshIntrospection.Rpc.FieldProcessing.FieldSelector` expects — its own
  fallback is `if is_atom(field_name), do: field_name, else: nil` — and it calls
  this twice per field: once with the client string, then again with whatever
  the first call returned. Answering `nil` to the second call made a mapped
  field unselectable: `"addressLine1"` resolved to `:address_line_1` and then
  back to `nil`, and the request failed with `unknown_field` naming no field at
  all (#71).

  Existence is not checked here. An unmapped atom is returned as given and the
  caller rejects it against the resource, which is what the shared default does.
  """
  def get_original_field_name(_resource, client_field_name) when is_atom(client_field_name),
    do: client_field_name

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
  The name a field takes on the wire, as a string.

  One answer for both directions of the contract: the key
  `AshKotlinMultiplatform.Rpc.Pipeline` writes into a response, and the key
  `AshKotlinMultiplatform.Codegen.ResourceSchemas` generates Kotlin to read.
  They were computed separately and disagreed — codegen camelized the attribute
  name and never read `field_names` at all — which is why the option was
  documented and dead on both sides (#71).

  A `field_names` override wins and is used verbatim, never re-formatted: the
  override *is* the client's chosen name, so `output_field_formatter
  :snake_case` does not turn `:addressLine1` into `address_line1`. Without an
  override the formatter decides, as before.

  Always a string. The DSL stores override values as atoms, and an atom key in a
  payload of string keys encodes to the right JSON while failing every
  `Map.get(data, "addressLine1")` in Elixir.
  """
  @spec client_field_name(module(), atom(), atom()) :: String.t()
  def client_field_name(resource, field_name, formatter) do
    case Keyword.get(kotlin_multiplatform_field_names(resource), field_name) do
      nil -> AshIntrospection.FieldFormatter.format_field_name(field_name, formatter)
      override -> to_string(override)
    end
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
  Returns the resource's public calculations that are fields on the struct.

  Ash stores a calculation declared `field?: false` in the record's
  `calculations` map rather than as a struct key, so the generator has nowhere
  to put it: it is absent from the Kotlin data class, from the filter input and
  from anything that reads a field off a record. Every call site that treats a
  calculation as a generatable field goes through here.
  """
  def public_field_calculations(resource) do
    resource
    |> Ash.Resource.Info.public_calculations()
    |> Enum.filter(&field_calculation?/1)
  end

  @doc """
  Whether a calculation is a field on the resource struct.

  Defaults to `true`, matching Ash's own default for the `field?` option.
  """
  def field_calculation?(calculation), do: Map.get(calculation, :field?, true)

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
