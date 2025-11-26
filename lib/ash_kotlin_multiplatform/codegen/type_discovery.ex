# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.TypeDiscovery do
  @moduledoc """
  Discovers all types that need Kotlin definitions generated.

  This module serves as the central type discovery system for the code generator.
  It recursively traverses the type dependency tree starting from RPC-configured
  resources to find all Ash resources that need Kotlin type definitions.

  ## Type Discovery

  The discovery process handles:
  - Ash resources (both embedded and non-embedded)
  - Complex nested types (unions, maps, arrays, etc.)
  - Recursive type references with cycle detection
  - Path tracking for diagnostic purposes

  ## Main Functions

  - `scan_rpc_resources/1` - Finds all Ash resources referenced by RPC resources
  - `find_embedded_resources/1` - Filters for embedded resources only
  - `get_rpc_resources/1` - Gets RPC-configured resources from domains

  ## Validation & Warnings

  - `find_non_rpc_referenced_resources/1` - Finds non-RPC resources referenced by RPC resources
  - `find_non_rpc_referenced_resources_with_paths/1` - Same as above but includes reference paths
  - `find_resources_missing_from_rpc_config/1` - Finds resources with extension but not configured
  - `build_rpc_warnings/1` - Builds formatted warning message for misconfigured resources
  """

  alias AshIntrospection.TypeSystem.Introspection
  alias AshKotlinMultiplatform.Rpc.Info

  @doc """
  Finds all Ash resources referenced by RPC resources.

  Recursively scans all public attributes, calculations, and aggregates of RPC resources,
  traversing complex types like maps with fields, unions, etc., to find any Ash resource references.

  ## Parameters

    * `otp_app` - The OTP application name to scan for domains and RPC resources

  ## Returns

  A list of unique Ash resource modules that are referenced by RPC resources.
  """
  def scan_rpc_resources(otp_app) do
    rpc_resources = get_rpc_resources(otp_app)

    rpc_resources
    |> Enum.reduce({[], MapSet.new()}, fn resource, {acc, visited} ->
      {found, new_visited} = scan_rpc_resource(resource, visited)
      {acc ++ found, new_visited}
    end)
    |> elem(0)
    |> Enum.map(fn {resource, _path} -> resource end)
    |> Enum.uniq()
  end

  @doc """
  Discovers embedded resources from RPC resources by scanning and filtering.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of embedded resource modules.
  """
  def find_embedded_resources(otp_app) do
    otp_app
    |> scan_rpc_resources()
    |> Enum.filter(&Introspection.is_embedded_resource?/1)
  end

  @doc """
  Gets all RPC resources configured in the given OTP application.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of unique resource modules that are configured as RPC resources in any domain.
  """
  def get_rpc_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = Info.kotlin_rpc(domain)
      Enum.map(rpc_config, fn %{resource: resource} -> resource end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Scans a single RPC resource to find all referenced resources.

  ## Parameters

    * `resource` - An Ash resource module
    * `visited` - A MapSet of already-visited resources (defaults to empty)

  ## Returns

  A tuple of `{found_resources, updated_visited}` where:
    * `found_resources` - List of `{resource, path}` tuples
    * `updated_visited` - Updated MapSet of visited resources
  """
  def scan_rpc_resource(resource, visited \\ MapSet.new()) do
    path = [{:root, resource}]
    find_referenced_resources_with_visited(resource, path, visited)
  end

  @doc """
  Finds all embedded resources referenced by a single resource.

  ## Parameters

    * `resource` - An Ash resource module to scan

  ## Returns

  A list of embedded resource modules.
  """
  def find_referenced_embedded_resources(resource) do
    resource
    |> find_referenced_resources()
    |> Enum.filter(&Ash.Resource.Info.embedded?/1)
  end

  @doc """
  Finds all Ash resources referenced by a single resource's public attributes,
  calculations, and aggregates.

  ## Parameters

    * `resource` - An Ash resource module to scan

  ## Returns

  A list of Ash resource modules referenced by the given resource.
  """
  def find_referenced_resources(resource) do
    path = [{:root, resource}]

    find_referenced_resources_with_visited(resource, path, MapSet.new())
    |> elem(0)
    |> Enum.map(fn {res, _path} -> res end)
    |> Enum.uniq()
  end

  @doc """
  Finds all non-RPC resources that are referenced by RPC resources.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of non-RPC resource modules that are referenced by RPC resources.
  """
  def find_non_rpc_referenced_resources(otp_app) do
    otp_app
    |> find_non_rpc_referenced_resources_with_paths()
    |> Map.keys()
  end

  @doc """
  Finds all non-RPC resources referenced by RPC resources, with paths showing where they're referenced.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A map where keys are non-RPC resource modules and values are lists of formatted path strings.
  """
  def find_non_rpc_referenced_resources_with_paths(otp_app) do
    rpc_resources = get_rpc_resources(otp_app)

    rpc_resources
    |> Enum.flat_map(fn rpc_resource ->
      path = [{:root, rpc_resource}]

      rpc_resource
      |> find_referenced_resources_with_visited(path, MapSet.new())
      |> elem(0)
    end)
    |> Enum.reject(fn {resource, _path} ->
      resource in rpc_resources or Ash.Resource.Info.embedded?(resource)
    end)
    |> group_by_resource_with_paths()
  end

  @doc """
  Finds resources with the AshKotlinMultiplatform.Resource extension that are not configured
  in any kotlin_rpc block.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of non-embedded resource modules with the extension but not configured for RPC.
  """
  def find_resources_missing_from_rpc_config(otp_app) do
    rpc_resources = get_rpc_resources(otp_app)

    all_resources_with_extension =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.uniq()
      |> Enum.filter(fn resource ->
        extensions = Spark.extensions(resource)
        AshKotlinMultiplatform.Resource in extensions
      end)

    Enum.reject(all_resources_with_extension, fn resource ->
      Ash.Resource.Info.embedded?(resource) or resource in rpc_resources
    end)
  end

  @doc """
  Builds a formatted warning message for resources that may be misconfigured.

  Returns a formatted warning string if any issues are found, or nil if everything
  is configured correctly.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A formatted warning string, or nil if no warnings are needed.
  """
  def build_rpc_warnings(otp_app) do
    warnings = []

    warnings =
      if AshKotlinMultiplatform.warn_on_missing_rpc_config?() do
        missing_resources = find_resources_missing_from_rpc_config(otp_app)

        if missing_resources != [] do
          [build_missing_config_warning(otp_app, missing_resources) | warnings]
        else
          warnings
        end
      else
        warnings
      end

    warnings =
      if AshKotlinMultiplatform.warn_on_non_rpc_references?() do
        referenced_non_rpc_with_paths = find_non_rpc_referenced_resources_with_paths(otp_app)

        if map_size(referenced_non_rpc_with_paths) > 0 do
          [build_non_rpc_references_warning(referenced_non_rpc_with_paths) | warnings]
        else
          warnings
        end
      else
        warnings
      end

    case warnings do
      [] -> nil
      parts -> Enum.join(Enum.reverse(parts), "\n\n")
    end
  end

  @doc """
  Recursively traverses a type and its constraints to find all Ash resource references.

  ## Parameters

    * `type` - The type to traverse (module or type atom)
    * `constraints` - The constraints keyword list for the type

  ## Returns

  A list of Ash resource modules found in the type tree.
  """
  def traverse_type(type, constraints) when is_list(constraints) do
    traverse_type_with_visited(type, constraints, [], MapSet.new())
    |> elem(0)
    |> Enum.map(fn {resource, _path} -> resource end)
    |> Enum.uniq()
  end

  def traverse_type(_type, _constraints), do: []

  @doc """
  Formats a path (list of path segments) into a human-readable string.

  ## Parameters

    * `path` - A list of path segments

  ## Returns

  A formatted string representing the path.
  """
  def format_path(path) do
    Enum.map_join(path, " -> ", &format_path_segment/1)
  end

  # Private functions

  defp format_path_segment({:root, module}) do
    module
    |> Module.split()
    |> List.last()
  end

  defp format_path_segment({:attribute, name}), do: to_string(name)
  defp format_path_segment({:calculation, name}), do: to_string(name)
  defp format_path_segment({:aggregate, name}), do: to_string(name)
  defp format_path_segment({:union_member, name}), do: "(union member: #{name})"
  defp format_path_segment(:array_items), do: "[]"
  defp format_path_segment({:map_field, name}), do: to_string(name)

  defp format_path_segment({:relationship_path, names}) do
    "(via relationships: #{Enum.join(names, " -> ")})"
  end

  defp group_by_resource_with_paths(resource_path_tuples) do
    resource_path_tuples
    |> Enum.group_by(
      fn {resource, _path} -> resource end,
      fn {_resource, path} -> format_path(path) end
    )
    |> Enum.map(fn {resource, paths} -> {resource, Enum.uniq(paths)} end)
    |> Enum.into(%{})
  end

  defp get_related_resource(resource, relationship_path) do
    Enum.reduce_while(relationship_path, resource, fn rel_name, current_resource ->
      case Ash.Resource.Info.relationship(current_resource, rel_name) do
        nil -> {:halt, nil}
        relationship -> {:cont, relationship.destination}
      end
    end)
  end

  defp find_referenced_resources_with_visited(resource, current_path, visited) do
    if MapSet.member?(visited, resource) do
      {[], visited}
    else
      visited = MapSet.put(visited, resource)

      attributes = Ash.Resource.Info.public_attributes(resource)
      calculations = get_public_calculations(resource)
      aggregates = get_public_aggregates(resource)

      {attribute_resources, visited} =
        Enum.reduce(attributes, {[], visited}, fn attr, {acc, visited} ->
          attr_path = current_path ++ [{:attribute, attr.name}]

          {found, new_visited} =
            traverse_type_with_visited(attr.type, attr.constraints || [], attr_path, visited)

          {acc ++ found, new_visited}
        end)

      {calculation_resources, visited} =
        Enum.reduce(calculations, {[], visited}, fn calc, {acc, visited} ->
          calc_path = current_path ++ [{:calculation, calc.name}]

          {found, new_visited} =
            traverse_type_with_visited(calc.type, calc.constraints || [], calc_path, visited)

          {acc ++ found, new_visited}
        end)

      {aggregate_resources, visited} =
        Enum.reduce(aggregates, {[], visited}, fn agg, {acc, visited} ->
          with true <- agg.kind in [:first, :list, :max, :min, :custom],
               true <- agg.field != nil and agg.relationship_path != [],
               related_resource when not is_nil(related_resource) <-
                 get_related_resource(resource, agg.relationship_path),
               field_attr when not is_nil(field_attr) <-
                 Ash.Resource.Info.attribute(related_resource, agg.field) do
            agg_path =
              current_path ++
                [{:aggregate, agg.name}, {:relationship_path, agg.relationship_path}]

            {found, new_visited} =
              traverse_type_with_visited(
                field_attr.type,
                field_attr.constraints || [],
                agg_path,
                visited
              )

            {acc ++ found, new_visited}
          else
            _ -> {acc, visited}
          end
        end)

      all_resources = attribute_resources ++ calculation_resources ++ aggregate_resources

      {all_resources, visited}
    end
  end

  defp get_public_calculations(resource) do
    try do
      Ash.Resource.Info.public_calculations(resource)
    rescue
      _ -> []
    end
  end

  defp get_public_aggregates(resource) do
    try do
      Ash.Resource.Info.public_aggregates(resource)
    rescue
      _ -> []
    end
  end

  defp traverse_type_with_visited(type, constraints, current_path, visited)
       when is_list(constraints) do
    case type do
      {:array, inner_type} ->
        items_constraints = Keyword.get(constraints, :items, [])
        array_path = current_path ++ [:array_items]
        traverse_type_with_visited(inner_type, items_constraints, array_path, visited)

      Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) do
          resource_path = current_path

          {nested, new_visited} =
            find_referenced_resources_with_visited(instance_of, resource_path, visited)

          {[{instance_of, resource_path}] ++ nested, new_visited}
        else
          {[], visited}
        end

      Ash.Type.Union ->
        union_types = Introspection.get_union_types_from_constraints(type, constraints)

        Enum.reduce(union_types, {[], visited}, fn {type_name, type_config}, {acc, visited} ->
          member_type = Keyword.get(type_config, :type)
          member_constraints = Keyword.get(type_config, :constraints, [])

          if member_type do
            union_path = current_path ++ [{:union_member, type_name}]

            {found, new_visited} =
              traverse_type_with_visited(member_type, member_constraints, union_path, visited)

            {acc ++ found, new_visited}
          else
            {acc, visited}
          end
        end)

      type when type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        fields = Keyword.get(constraints, :fields)

        if fields do
          traverse_fields_with_visited(fields, current_path, visited)
        else
          {[], visited}
        end

      type when is_atom(type) ->
        cond do
          Ash.Resource.Info.resource?(type) ->
            resource_path = current_path

            {nested, new_visited} =
              find_referenced_resources_with_visited(type, resource_path, visited)

            {[{type, resource_path}] ++ nested, new_visited}

          Code.ensure_loaded?(type) ->
            fields = Keyword.get(constraints, :fields)

            if fields do
              traverse_fields_with_visited(fields, current_path, visited)
            else
              {[], visited}
            end

          true ->
            {[], visited}
        end

      _ ->
        {[], visited}
    end
  end

  defp traverse_type_with_visited(_type, _constraints, _current_path, visited),
    do: {[], visited}

  defp traverse_fields_with_visited(fields, current_path, visited) when is_list(fields) do
    Enum.reduce(fields, {[], visited}, fn {field_name, field_config}, {acc, visited} ->
      field_type = Keyword.get(field_config, :type)
      field_constraints = Keyword.get(field_config, :constraints, [])

      if field_type do
        field_path = current_path ++ [{:map_field, field_name}]

        {found, new_visited} =
          traverse_type_with_visited(field_type, field_constraints, field_path, visited)

        {acc ++ found, new_visited}
      else
        {acc, visited}
      end
    end)
  end

  defp traverse_fields_with_visited(_, _current_path, visited), do: {[], visited}

  defp build_missing_config_warning(otp_app, missing_resources) do
    lines = [
      "⚠️  Found resources with AshKotlinMultiplatform.Resource extension",
      "   but not listed in any domain's kotlin_rpc block:",
      ""
    ]

    resource_lines =
      missing_resources
      |> Enum.map(fn resource -> "   • #{inspect(resource)}" end)

    explanation_lines = [
      "",
      "   These resources will not have Kotlin types generated.",
      "   To fix this, add them to a domain's kotlin_rpc block:",
      ""
    ]

    example_lines = build_example_config(otp_app, missing_resources)

    (lines ++ resource_lines ++ explanation_lines ++ example_lines)
    |> Enum.join("\n")
  end

  defp build_example_config(otp_app, missing_resources) do
    example_domain =
      otp_app
      |> Ash.Info.domains()
      |> List.first()

    if example_domain do
      domain_name = inspect(example_domain)
      example_resource = missing_resources |> List.first() |> inspect()

      [
        "   defmodule #{domain_name} do",
        "     use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]",
        "",
        "     kotlin_rpc do",
        "       resource #{example_resource}",
        "     end",
        "   end"
      ]
    else
      []
    end
  end

  defp build_non_rpc_references_warning(referenced_non_rpc_with_paths) do
    lines = [
      "⚠️  Found non-RPC resources referenced by RPC resources:",
      ""
    ]

    resource_lines =
      referenced_non_rpc_with_paths
      |> Enum.sort_by(fn {resource, _paths} -> inspect(resource) end)
      |> Enum.flat_map(fn {resource, paths} ->
        resource_line = "   • #{inspect(resource)}"
        ref_header = "     Referenced from:"

        path_lines =
          paths
          |> Enum.sort()
          |> Enum.map(fn path -> "       - #{path}" end)

        [resource_line, ref_header] ++ path_lines ++ [""]
      end)

    explanation_lines = [
      "   These resources are referenced in attributes, calculations, or aggregates",
      "   of RPC resources, but are not themselves configured as RPC resources.",
      "   They will NOT have Kotlin types or RPC functions generated.",
      "",
      "   If these resources should be accessible via RPC, add them to a domain's",
      "   kotlin_rpc block. Otherwise, you can ignore this warning."
    ]

    (lines ++ resource_lines ++ explanation_lines)
    |> Enum.join("\n")
  end
end
