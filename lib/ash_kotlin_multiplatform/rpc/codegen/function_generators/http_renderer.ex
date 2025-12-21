# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.FunctionGenerators.HttpRenderer do
  @moduledoc """
  Renders HTTP-specific Kotlin suspend functions (Ktor-based).

  Takes the function "shape" from FunctionCore and renders it as
  a Kotlin suspend function using Ktor HttpClient.
  """

  alias AshKotlinMultiplatform.Rpc.Codegen.FunctionGenerators.FunctionCore
  alias AshKotlinMultiplatform.Rpc.Codegen.Helpers.{ConfigBuilder, PayloadBuilder}
  alias AshIntrospection.Helpers

  @doc """
  Renders an HTTP execution function (suspend function with Ktor).
  """
  def render_execution_function(resource, action, rpc_action, rpc_action_name) do
    shape =
      FunctionCore.build_execution_function_shape(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        transport: :http
      )

    function_name = Helpers.snake_to_camel_case(rpc_action_name)
    config_name = "#{shape.rpc_action_name_pascal}Config"
    endpoint = AshKotlinMultiplatform.run_endpoint()

    # Generate the config type
    config_type =
      ConfigBuilder.generate_config_type(resource, action, rpc_action, rpc_action_name)

    # Generate payload construction code
    payload_code =
      PayloadBuilder.build_payload_code(
        rpc_action_name,
        shape.context,
        include_fields: shape.has_fields,
        include_metadata_fields: shape.has_metadata
      )

    """
    #{config_type}
    suspend fun #{function_name}(
        client: HttpClient,
        config: #{config_name},
        endpoint: String = "#{endpoint}"
    ): RpcResult<Map<String, Any?>> {
        return client.post(endpoint) {
            contentType(ContentType.Application.Json)
            config.headers.forEach { (key, value) ->
                header(key, value)
            }
            setBody(buildJsonObject {
                #{payload_code}
            })
        }.body()
    }
    """
  end

  @doc """
  Renders an HTTP validation function.
  """
  def render_validation_function(resource, action, rpc_action, rpc_action_name) do
    shape =
      FunctionCore.build_validation_function_shape(
        resource,
        action,
        rpc_action,
        rpc_action_name
      )

    function_name = "validate#{shape.rpc_action_name_pascal}"
    endpoint = AshKotlinMultiplatform.validate_endpoint()

    # Generate validation-specific config
    config_type = generate_validation_config_type(shape)

    # Generate payload construction code
    payload_code = PayloadBuilder.build_validation_payload_code(rpc_action_name, shape.context)

    """
    #{config_type}
    suspend fun #{function_name}(
        client: HttpClient,
        config: #{shape.rpc_action_name_pascal}ValidationConfig,
        endpoint: String = "#{endpoint}"
    ): ValidationResult {
        return client.post(endpoint) {
            contentType(ContentType.Application.Json)
            config.headers.forEach { (key, value) ->
                header(key, value)
            }
            setBody(buildJsonObject {
                #{payload_code}
            })
        }.body()
    }
    """
  end

  defp generate_validation_config_type(shape) do
    fields = []

    # Add tenant if required
    fields =
      if shape.context.requires_tenant do
        fields ++ ["    val tenant: String"]
      else
        fields
      end

    # Add input field based on input type
    fields =
      case shape.context.action_input_type do
        :required ->
          fields ++ ["    val input: #{shape.rpc_action_name_pascal}Input"]

        :optional ->
          fields ++ ["    val input: #{shape.rpc_action_name_pascal}Input? = null"]

        :none ->
          fields
      end

    # Add headers field
    fields = fields ++ ["    val headers: Map<String, String> = emptyMap()"]

    """
    data class #{shape.rpc_action_name_pascal}ValidationConfig(
    #{Enum.join(fields, ",\n")}
    )
    """
  end
end
