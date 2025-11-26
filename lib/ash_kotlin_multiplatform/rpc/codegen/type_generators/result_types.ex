# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.ResultTypes do
  @moduledoc """
  Generates Kotlin result types for Ash actions.

  Creates sealed classes that represent the success/error results for each RPC action,
  providing type-safe result handling in Kotlin.
  """

  alias AshIntrospection.Helpers

  @doc """
  Generates result types for all RPC actions in the given domain configuration.
  """
  def generate_result_types(rpc_configs) do
    rpc_configs
    |> Enum.flat_map(fn %{resource: resource, rpc_actions: actions} ->
      Enum.map(actions, fn action ->
        generate_result_type(resource, action)
      end)
    end)
    |> Enum.join("\n\n")
  end

  @doc """
  Generates a Kotlin sealed class result type for a specific action.
  """
  def generate_result_type(resource, %{name: rpc_name, action: action_name}) do
    action = Ash.Resource.Info.action(resource, action_name)
    result_class_name = "#{Helpers.snake_to_pascal_case(rpc_name)}Result"
    resource_type = get_kotlin_type_name(resource)

    # Determine the data type based on action type
    data_type =
      if action do
        case action.type do
          :read -> "List<#{resource_type}>"
          :create -> resource_type
          :update -> resource_type
          :destroy -> resource_type
          :action -> determine_action_return_type(action, resource_type)
          _ -> resource_type
        end
      else
        resource_type
      end

    """
    @Serializable
    sealed class #{result_class_name} {
        abstract val success: Boolean

        @Serializable
        @SerialName("success")
        data class Success(
            override val success: Boolean = true,
            val data: #{data_type},
            val metadata: Map<String, @Contextual Any?>? = null
        ) : #{result_class_name}()

        @Serializable
        @SerialName("error")
        data class Error(
            override val success: Boolean = false,
            val errors: List<AshRpcError>
        ) : #{result_class_name}()
    }
    """
  end

  defp determine_action_return_type(action, default_type) do
    case action.returns do
      nil -> default_type
      {:array, _inner} -> "List<#{default_type}>"
      _ -> default_type
    end
  end

  defp get_kotlin_type_name(resource) do
    case AshKotlinMultiplatform.Resource.Info.kotlin_type_name(resource) do
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
end
