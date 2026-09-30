# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen do
  @moduledoc """
  Main orchestrator for Kotlin code generation.

  This module coordinates the generation of all Kotlin code from Ash resources,
  including:
  - Data classes for resources
  - Enum classes for atom types with :one_of constraints
  - Sealed classes for union types
  - Input types for actions
  - `RpcResult<T>`, the wrapper every RPC function returns
  - `AshPage<T>`, what a read's `data` decodes into
  - `AshMetadata<T, M>`, what a mutation with exposed metadata returns
  - Metadata types for action metadata
  - RPC functions (both functional and object-oriented styles)
  - Validation functions (if enabled)
  - Phoenix Channel client (if enabled)
  """

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Codegen.{Declarations, FilterTypes, ResourceSchemas, TypedQueries}

  alias AshKotlinMultiplatform.Rpc.Codegen.{
    KotlinStatic,
    RpcConfigCollector
  }

  alias AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.{
    InputTypes,
    MetadataTypes,
    PaginationTypes
  }

  alias AshKotlinMultiplatform.Rpc.Codegen.FunctionGenerators.HttpRenderer
  alias AshKotlinMultiplatform.Rpc.Codegen.PhoenixChannel
  alias AshIntrospection.Helpers

  @doc """
  Generates Kotlin code for the given OTP application.

  ## Parameters
  - `otp_app` - The OTP application name
  - `opts` - Generation options

  ## Returns
  `{:ok, kotlin_code}` or `{:error, reason}`
  """
  def generate_kotlin_code(otp_app, opts \\ []) do
    package_name = get_package_name(otp_app, opts)

    # Collect RPC configuration using the collector
    rpc_resources = RpcConfigCollector.get_rpc_resources(otp_app)

    if Enum.empty?(rpc_resources) do
      {:error, "No RPC resources found for #{otp_app}"}
    else
      # Run verifiers if not in development/test mode
      domains = Ash.Info.domains(otp_app)

      case AshKotlinMultiplatform.VerifierChecker.check_all_verifiers(rpc_resources ++ domains) do
        :ok ->
          case Declarations.check(declaration_fragments(otp_app, opts)) do
            :ok ->
              generate_full_kotlin_code(otp_app, package_name, rpc_resources, opts)

            {:error, error_message} ->
              {:error, error_message}
          end

        {:error, error_message} ->
          {:error, error_message}
      end
    end
  end

  defp generate_full_kotlin_code(otp_app, package_name, rpc_resources, opts) do
    # Get RPC configs for input/result type generation
    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(otp_app)
    rpc_configs = RpcConfigCollector.get_rpc_configs(otp_app)

    embedded = Manifest.embedded_resources()

    # Every resource this pass declares a class for. `TypeMapper` reads the same
    # list, so a field and a function signature cannot disagree about which
    # classes exist (#87, #91).
    emitted = Manifest.published_resources()

    # Generate comprehensive schema types
    {data_classes, embedded_classes, enum_classes, sealed_classes} =
      ResourceSchemas.generate_all_schemas(rpc_resources, embedded)

    # Generate action-specific input types
    input_types = InputTypes.generate_input_types(rpc_configs)

    # Generate metadata types for actions that expose metadata
    metadata_types = generate_metadata_types(resources_and_actions)

    # Generate filter types if enabled
    filter_types =
      if Keyword.get(opts, :with_filters, AshKotlinMultiplatform.generate_filter_types?()) do
        FilterTypes.generate_all_filter_types(otp_app)
      else
        ""
      end

    # Generate typed queries if any exist
    typed_queries = TypedQueries.generate_from_config(otp_app)

    # Generate validation types if validation functions are enabled
    validation_types =
      if AshKotlinMultiplatform.generate_validation_functions?() do
        KotlinStatic.generate_validation_types()
      else
        ""
      end

    kotlin_code =
      [
        generate_header(package_name),
        KotlinStatic.generate_imports(opts),
        KotlinStatic.generate_type_aliases(),
        KotlinStatic.generate_money_type(),
        KotlinStatic.generate_shared_json(),
        KotlinStatic.generate_http_client_factory(),
        KotlinStatic.generate_error_types(),
        # Resource data classes
        non_empty_or_nil(data_classes, "// Resource Data Classes"),
        # Embedded resource classes
        non_empty_or_nil(embedded_classes, "// Embedded Resource Classes"),
        # Enum classes for atom types with :one_of
        non_empty_or_nil(enum_classes, "// Enum Classes"),
        # Sealed classes for union types
        non_empty_or_nil(sealed_classes, "// Union Sealed Classes"),
        # Generic result types
        KotlinStatic.generate_generic_result_types(),
        # Validation types (if enabled)
        non_empty_or_nil(validation_types, "// Validation Types"),
        # The page a read returns
        "// Pagination Types\n#{PaginationTypes.generate_page_type()}",
        # The envelope a mutation with exposed metadata returns
        "// Metadata Envelope\n#{MetadataTypes.generate_metadata_envelope_type()}",
        # Metadata types
        non_empty_or_nil(metadata_types, "// Metadata Types"),
        # Input types for actions
        non_empty_or_nil(input_types, "// Action Input Types"),
        # Filter types (if enabled)
        non_empty_or_nil(filter_types, "// Filter Types"),
        # Typed queries (if any)
        non_empty_or_nil(typed_queries, "// Typed Queries"),
        # RPC functions (functional style with config types)
        non_empty_or_nil(
          generate_rpc_functions(resources_and_actions, emitted),
          "// RPC Functions"
        ),
        # Validation functions (if enabled)
        maybe_generate_validation_functions(resources_and_actions, opts),
        # Object wrappers (OO style), from the configs collected above rather
        # than a second walk of the domains
        non_empty_or_nil(
          render_object_wrappers(rpc_configs, package_name),
          "// Object-Oriented API"
        ),
        # Phoenix Channel client (if enabled)
        maybe_generate_channel_client()
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    {:ok, kotlin_code}
  end

  @doc """
  Every `{source, fragment}` pair a full generation pass would declare, for
  `Codegen.Declarations.check/1`.

  Calls the exact same per-item generator functions `generate_kotlin_code/2`
  calls with the exact same inputs — every generator here is pure, so a
  second call is never an approximation of the real output; it recomputes
  the same bytes. `ResourceSchemas.generate_all_schemas_fragments/2` is the
  one exception carrying real behaviour: it keeps a same-named duplicate
  `generate_all_schemas/2` still drops.
  """
  def declaration_fragments(otp_app, opts \\ []) do
    package_name = get_package_name(otp_app, opts)
    rpc_resources = RpcConfigCollector.get_rpc_resources(otp_app)
    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(otp_app)
    rpc_configs = RpcConfigCollector.get_rpc_configs(otp_app)
    embedded = Manifest.embedded_resources()
    emitted = Manifest.published_resources()

    schema_fragments =
      ResourceSchemas.generate_all_schemas_fragments(rpc_resources, embedded)

    rpc_action_fragments =
      Enum.map(resources_and_actions, fn {resource, action, rpc_action} ->
        {"rpc_action :#{rpc_action.name} on #{inspect(resource)}",
         HttpRenderer.render_execution_function(
           resource,
           action,
           rpc_action,
           rpc_action.name,
           emitted
         )}
      end)

    validation_fragments =
      if AshKotlinMultiplatform.generate_validation_functions?() do
        resources_and_actions
        |> Enum.filter(fn {_resource, action, _rpc_action} ->
          action.type in [:create, :update]
        end)
        |> Enum.map(fn {resource, action, rpc_action} ->
          {"validation for rpc_action :#{rpc_action.name} on #{inspect(resource)}",
           HttpRenderer.render_validation_function(resource, action, rpc_action, rpc_action.name)}
        end)
      else
        []
      end

    metadata_fragments =
      Enum.flat_map(resources_and_actions, fn {resource, action, rpc_action} ->
        case MetadataTypes.generate_action_metadata_type(action, rpc_action, rpc_action.name) do
          "" ->
            []

          fragment ->
            [{"metadata for rpc_action :#{rpc_action.name} on #{inspect(resource)}", fragment}]
        end
      end)

    input_fragments =
      Enum.flat_map(rpc_configs, fn %{resource: resource, rpc_actions: actions} ->
        Enum.map(actions, fn rpc_action ->
          {"rpc_action :#{rpc_action.name} on #{inspect(resource)} (input class)",
           InputTypes.generate_input_type(resource, rpc_action)}
        end)
      end)

    filter_fragments =
      if Keyword.get(opts, :with_filters, AshKotlinMultiplatform.generate_filter_types?()) do
        filter_resources =
          otp_app
          |> Ash.Info.domains()
          |> Enum.flat_map(&Ash.Domain.Info.resources/1)
          |> Enum.uniq()

        [
          {"built-in (FilterTypes.generate_base_filter_types/0)",
           FilterTypes.generate_base_filter_types()}
        ] ++
          Enum.map(filter_resources, fn resource ->
            {"resource #{inspect(resource)} (filter type)",
             FilterTypes.generate_filter_type(resource)}
          end)
      else
        []
      end

    typed_query_fragments =
      Enum.map(RpcConfigCollector.get_typed_queries(otp_app), fn {resource, action, typed_query} ->
        {"typed_query :#{typed_query.name} on #{inspect(resource)}",
         TypedQueries.generate_typed_query_type_and_const(
           resource,
           action,
           typed_query,
           rpc_resources
         )}
      end)

    object_wrapper_fragments =
      rpc_configs
      |> Enum.group_by(fn %{resource: resource} -> resource end)
      |> Enum.map(fn {resource, configs} ->
        actions = Enum.flat_map(configs, fn %{rpc_actions: actions} -> actions end)

        {"object wrapper for #{inspect(resource)}",
         generate_object_wrapper(resource, actions, package_name)}
      end)

    built_in_fragments =
      KotlinStatic.reserved_top_level_names(opts) ++
        [
          {"built-in (KotlinStatic.generate_type_aliases/0)",
           KotlinStatic.generate_type_aliases()},
          {"built-in (KotlinStatic.generate_money_type/0)", KotlinStatic.generate_money_type()},
          {"built-in (KotlinStatic.generate_shared_json/0)", KotlinStatic.generate_shared_json()},
          {"built-in (KotlinStatic.generate_http_client_factory/0)",
           KotlinStatic.generate_http_client_factory()},
          {"built-in (KotlinStatic.generate_error_types/0)", KotlinStatic.generate_error_types()},
          {"built-in (KotlinStatic.generate_generic_result_types/0)",
           KotlinStatic.generate_generic_result_types()},
          {"built-in (PaginationTypes.generate_page_type/0)",
           PaginationTypes.generate_page_type()},
          {"built-in (MetadataTypes.generate_metadata_envelope_type/0)",
           MetadataTypes.generate_metadata_envelope_type()}
        ]

    validation_type_fragments =
      if AshKotlinMultiplatform.generate_validation_functions?() do
        [
          {"built-in (KotlinStatic.generate_validation_types/0)",
           KotlinStatic.generate_validation_types()}
        ]
      else
        []
      end

    channel_fragments =
      if AshKotlinMultiplatform.generate_phoenix_channel_client?() do
        [{"built-in (PhoenixChannel.generate/0)", PhoenixChannel.generate()}]
      else
        []
      end

    built_in_fragments ++
      validation_type_fragments ++
      channel_fragments ++
      schema_fragments ++
      rpc_action_fragments ++
      validation_fragments ++
      metadata_fragments ++
      input_fragments ++
      filter_fragments ++
      typed_query_fragments ++
      object_wrapper_fragments
  end

  defp non_empty_or_nil(content, _header) when content in [nil, ""], do: nil
  defp non_empty_or_nil(content, header), do: "#{header}\n#{content}"

  defp get_package_name(otp_app, opts) do
    case Keyword.get(opts, :package_name) || AshKotlinMultiplatform.default_package_name() do
      nil ->
        # Auto-generate from otp_app
        app_name =
          otp_app
          |> Atom.to_string()
          |> String.replace("_", "")

        "com.#{app_name}.ash"

      name ->
        name
    end
  end

  defp generate_header(package_name) do
    """
    // Generated by AshKotlinMultiplatform - Do not edit manually
    // https://github.com/ash-project/ash_interop

    package #{package_name}
    """
  end

  # Generate metadata types for all actions that expose metadata
  defp generate_metadata_types(resources_and_actions) do
    resources_and_actions
    |> Enum.map(fn {_resource, action, rpc_action} ->
      MetadataTypes.generate_action_metadata_type(action, rpc_action, rpc_action.name)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # Generate RPC functions using the HttpRenderer
  defp generate_rpc_functions(resources_and_actions, emitted) do
    resources_and_actions
    |> Enum.map(fn {resource, action, rpc_action} ->
      HttpRenderer.render_execution_function(
        resource,
        action,
        rpc_action,
        rpc_action.name,
        emitted
      )
    end)
    |> Enum.join("\n\n")
  end

  # Generate validation functions if enabled
  defp maybe_generate_validation_functions(resources_and_actions, _opts) do
    if AshKotlinMultiplatform.generate_validation_functions?() do
      validation_functions =
        resources_and_actions
        |> Enum.filter(fn {_resource, action, _rpc_action} ->
          # Only generate validation for actions that have input
          action.type in [:create, :update]
        end)
        |> Enum.map(fn {resource, action, rpc_action} ->
          HttpRenderer.render_validation_function(resource, action, rpc_action, rpc_action.name)
        end)
        |> Enum.join("\n\n")

      non_empty_or_nil(validation_functions, "// Validation Functions")
    else
      nil
    end
  end

  # The object-oriented API section: one `object <Type>Rpc` per RPC resource,
  # ordered by the type name the wrapper carries.
  #
  # `Enum.group_by/2` returns a map, and map iteration over atom keys follows the
  # atom table — creation order — not the alphabet, so before #43 this section
  # came out in a different order on every build. The sort makes the order a
  # property of the source rather than of what the VM loaded first. The resource
  # module is the tiebreak: `type_name` is unique among resources that use
  # `AshKotlinMultiplatform.Resource` (`VerifyUniqueTypeNames`), and two that do
  # not can both fall back to the same last module segment.
  #
  # Public for the ordering test, which builds the config list by hand so the
  # assertion does not depend on the running build's atom table.
  @doc false
  def render_object_wrappers(rpc_configs, package_name) do
    rpc_configs
    |> Enum.group_by(fn %{resource: resource} -> resource end)
    |> Enum.sort_by(fn {resource, _configs} ->
      {to_string(AshKotlinMultiplatform.Resource.Info.kotlin_multiplatform_type_name!(resource)),
       resource}
    end)
    |> Enum.map_join("\n\n", fn {resource, configs} ->
      # A resource exposed from two domains' kotlin_rpc blocks used to keep
      # only the first domain's actions (`List.first(configs)`) — merge
      # every domain's rpc_actions onto the one object instead (#33 row 16).
      actions = Enum.flat_map(configs, fn %{rpc_actions: actions} -> actions end)
      generate_object_wrapper(resource, actions, package_name)
    end)
  end

  defp generate_object_wrapper(resource, actions, package_name) do
    type_name = AshKotlinMultiplatform.Resource.Info.kotlin_multiplatform_type_name!(resource)
    object_name = "#{type_name}Rpc"

    functions =
      actions
      |> Enum.map(fn %{name: name} ->
        function_name = Helpers.snake_to_camel_case(name)
        config_name = "#{Helpers.snake_to_pascal_case(name)}Config"

        # Determine method name for OO API
        method_name = determine_method_name(name)

        # Qualify with package name to avoid recursive call when method_name matches function_name
        "    suspend fun #{method_name}(client: HttpClient, config: #{config_name}) = #{package_name}.#{function_name}(client, config)"
      end)
      |> Enum.join("\n")

    """
    object #{object_name} {
    #{functions}
    }
    """
  end

  defp determine_method_name(action_name) do
    name_str = Atom.to_string(action_name)

    cond do
      String.starts_with?(name_str, "list_") -> "list"
      String.starts_with?(name_str, "get_") -> "get"
      String.starts_with?(name_str, "create_") -> "create"
      String.starts_with?(name_str, "update_") -> "update"
      String.starts_with?(name_str, "delete_") -> "delete"
      String.starts_with?(name_str, "destroy_") -> "destroy"
      true -> Helpers.snake_to_camel_case(action_name)
    end
  end

  defp maybe_generate_channel_client do
    if AshKotlinMultiplatform.generate_phoenix_channel_client?() do
      "// Phoenix Channel Client\n// Note: Requires Ktor WebSocket client dependency\n\n" <>
        PhoenixChannel.generate()
    else
      nil
    end
  end
end
