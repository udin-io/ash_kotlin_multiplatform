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

  @doc """
  The type one element of a generic action's result has, as
  `{type, constraints}`.

  Drops a top-level `{:array, _}` and takes its `:items` constraints, then
  unwraps a NewType with
  `AshIntrospection.TypeSystem.Introspection.unwrap_new_type/3`. That is the
  order `AshIntrospection.Rpc.FieldProcessing.FieldSelector.select_fields/5`
  unwraps in, so codegen and the runner see the type the field selector sees.

  Returns `nil` for an action that is not generic or declares no return type.
  """
  @spec returned_type(Ash.Resource.Actions.action()) :: {term(), keyword()} | nil
  def returned_type(%{type: :action, returns: returns} = action) when not is_nil(returns) do
    constraints = action.constraints || []

    {type, constraints} =
      case returns do
        {:array, inner} -> {inner, Keyword.get(constraints, :items, [])}
        type -> {type, constraints}
      end

    AshIntrospection.TypeSystem.Introspection.unwrap_new_type(type, constraints)
  end

  def returned_type(_action), do: nil

  @doc """
  The resource a generic action returns, or `nil` when it returns none.

  A bare resource module (embedded ones included), a `:struct` whose
  `instance_of` is a resource, a NewType over either, and a list of any of
  them all name that resource. `Book.summarize` returns `Summary` and
  `Book.sample_author` returns `Author`, never `Book`.

  Codegen names the Kotlin class from this (#87), and `Rpc.Runner` takes the
  default fields of a request with no `fields` from it (#88). Returns `nil`
  for a read, create, update or destroy: those return the resource that owns
  them, which the action struct does not carry.
  """
  @spec returned_resource(Ash.Resource.Actions.action()) :: module() | nil
  def returned_resource(action) do
    case returned_type(action) do
      {Ash.Type.Struct, constraints} ->
        resource_or_nil(Keyword.get(constraints, :instance_of))

      {type, _constraints} ->
        resource_or_nil(type)

      nil ->
        nil
    end
  end

  defp resource_or_nil(module) do
    if Ash.Resource.Info.resource?(module), do: module
  end
end
