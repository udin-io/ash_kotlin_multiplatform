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
  - Result types (sealed classes for success/error)
  - Pagination types (offset, keyset, mixed)
  - Metadata types for action metadata
  - RPC functions (both functional and object-oriented styles)
  - Validation functions (if enabled)
  - Phoenix Channel client (if enabled)
  """

  alias AshKotlinMultiplatform.Rpc.Info
  alias AshKotlinMultiplatform.Codegen.{FilterTypes, ResourceSchemas, TypedQueries}

  alias AshKotlinMultiplatform.Rpc.Codegen.{
    KotlinStatic,
    RpcConfigCollector
  }

  alias AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.{
    InputTypes,
    MetadataTypes,
    PaginationTypes,
    ResultTypes
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
          generate_full_kotlin_code(otp_app, package_name, rpc_resources, opts)

        {:error, error_message} ->
          {:error, error_message}
      end
    end
  end

  defp generate_full_kotlin_code(otp_app, package_name, rpc_resources, opts) do
    # Get RPC configs for input/result type generation
    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(otp_app)
    rpc_configs = RpcConfigCollector.get_rpc_configs(otp_app)

    # Generate comprehensive schema types
    {data_classes, embedded_classes, enum_classes, sealed_classes} =
      ResourceSchemas.generate_all_schemas(rpc_resources)

    # Generate action-specific input types
    input_types = InputTypes.generate_input_types(rpc_configs)

    # Generate action-specific result types
    action_result_types = ResultTypes.generate_result_types(rpc_configs)

    # Generate metadata types for actions that expose metadata
    metadata_types = generate_metadata_types(resources_and_actions)

    # Generate pagination types for actions that support pagination
    pagination_types = generate_pagination_types(resources_and_actions)

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
        # Pagination types
        non_empty_or_nil(pagination_types, "// Pagination Types"),
        # Metadata types
        non_empty_or_nil(metadata_types, "// Metadata Types"),
        # Action-specific result types
        non_empty_or_nil(action_result_types, "// Action Result Types"),
        # Input types for actions
        non_empty_or_nil(input_types, "// Action Input Types"),
        # Filter types (if enabled)
        non_empty_or_nil(filter_types, "// Filter Types"),
        # Typed queries (if any)
        non_empty_or_nil(typed_queries, "// Typed Queries"),
        # RPC functions (functional style with config types)
        non_empty_or_nil(generate_rpc_functions(resources_and_actions, opts), "// RPC Functions"),
        # Validation functions (if enabled)
        maybe_generate_validation_functions(resources_and_actions, opts),
        # Object wrappers (OO style)
        non_empty_or_nil(generate_object_wrappers(otp_app), "// Object-Oriented API"),
        # Phoenix Channel client (if enabled)
        maybe_generate_channel_client()
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    {:ok, kotlin_code}
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

  defp get_resource_type_name(resource) do
    case AshKotlinMultiplatform.Resource.Info.kotlin_multiplatform_type_name(resource) do
      nil ->
        resource
        |> Module.split()
        |> List.last()

      name ->
        name
    end
  rescue
    _ ->
      resource
      |> Module.split()
      |> List.last()
  end

  # Generate pagination types for all paginated actions
  defp generate_pagination_types(resources_and_actions) do
    resources_and_actions
    |> Enum.filter(fn {_resource, action, _rpc_action} ->
      action.type == :read and PaginationTypes.action_supports_pagination?(action)
    end)
    |> Enum.map(fn {resource, action, rpc_action} ->
      resource_name = get_resource_type_name(resource)

      PaginationTypes.generate_pagination_result_type(
        resource,
        action,
        rpc_action.name,
        resource_name,
        false
      )
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
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
  defp generate_rpc_functions(resources_and_actions, _opts) do
    resources_and_actions
    |> Enum.map(fn {resource, action, rpc_action} ->
      HttpRenderer.render_execution_function(resource, action, rpc_action, rpc_action.name)
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

  defp generate_object_wrappers(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(&Info.kotlin_rpc/1)
    |> Enum.group_by(fn %{resource: resource} -> resource end)
    |> Enum.map(fn {resource, configs} ->
      generate_object_wrapper(resource, List.first(configs))
    end)
    |> Enum.join("\n\n")
  end

  defp generate_object_wrapper(resource, %{rpc_actions: actions}) do
    type_name = get_resource_type_name(resource)
    object_name = "#{type_name}Rpc"

    functions =
      actions
      |> Enum.map(fn %{name: name} ->
        function_name = Helpers.snake_to_camel_case(name)
        config_name = "#{Helpers.snake_to_pascal_case(name)}Config"

        # Determine method name for OO API
        method_name = determine_method_name(name)

        "    suspend fun #{method_name}(client: HttpClient, config: #{config_name}) = #{function_name}(client, config)"
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
