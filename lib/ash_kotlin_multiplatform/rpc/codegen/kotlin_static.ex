# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic do
  @moduledoc """
  Generates static Kotlin code components that are included in every generated file.

  This includes imports, utility types, error types, and helper functions.
  """

  @doc """
  Generates the standard imports for the generated Kotlin file.
  """
  def generate_imports(opts \\ []) do
    datetime_imports =
      case AshKotlinMultiplatform.datetime_library() do
        :kotlinx_datetime -> "import kotlinx.datetime.*"
        :java_time -> "import java.time.*"
      end

    websocket_imports =
      if AshKotlinMultiplatform.generate_phoenix_channel_client?() do
        """
        import io.ktor.client.plugins.websocket.*
        import io.ktor.websocket.*
        import kotlinx.coroutines.*
        """
      else
        ""
      end

    validation_imports =
      if Keyword.get(opts, :with_validation, false) do
        """
        import javax.validation.constraints.*
        """
      else
        ""
      end

    """
    import kotlinx.serialization.*
    import kotlinx.serialization.json.*
    #{datetime_imports}
    import io.ktor.client.*
    import io.ktor.client.call.*
    import io.ktor.client.request.*
    import io.ktor.client.plugins.contentnegotiation.*
    import io.ktor.serialization.kotlinx.json.*
    import io.ktor.http.*
    #{websocket_imports}#{validation_imports}
    """
    |> String.trim()
  end

  @doc """
  Generates a helper function to create a configured HttpClient.
  """
  def generate_http_client_factory do
    """
    // HTTP Client factory
    fun createHttpClient(): HttpClient {
        return HttpClient {
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true
                })
            }
        }
    }
    """
  end

  @doc """
  Generates type aliases for common types.
  """
  def generate_type_aliases do
    """
    // Type aliases for common types
    typealias UUID = String
    typealias Decimal = String
    """
  end

  @doc """
  Generates the RPC error types.
  """
  def generate_error_types do
    """
    // RPC Error types
    @Serializable
    data class AshRpcError(
        val type: String? = null,
        val message: String? = null,
        @SerialName("short_message")
        val shortMessage: String? = null,
        val vars: Map<String, String> = emptyMap(),
        val fields: List<String> = emptyList(),
        val path: List<String> = emptyList(),
        val details: Map<String, @Contextual Any?>? = null
    )
    """
  end

  @doc """
  Generates the generic RPC result types.
  """
  def generate_generic_result_types do
    """
    // Generic result wrapper
    @Serializable
    data class RpcResult(
        val success: Boolean,
        val data: JsonElement? = null,
        val errors: List<AshRpcError>? = null,
        val metadata: JsonElement? = null
    ) {
        inline fun <reified T> dataAs(): T? {
            return data?.let { Json { ignoreUnknownKeys = true }.decodeFromJsonElement<T>(it) }
        }

        fun isSuccess(): Boolean = success
        fun isError(): Boolean = !success
    }
    """
  end

  @doc """
  Generates the validation result type.
  """
  def generate_validation_types do
    """
    // Validation result types
    @Serializable
    sealed class ValidationResult {
        abstract val valid: Boolean
    }

    @Serializable
    @SerialName("valid")
    data class ValidationValid(
        override val valid: Boolean = true
    ) : ValidationResult()

    @Serializable
    @SerialName("invalid")
    data class ValidationInvalid(
        override val valid: Boolean = false,
        val errors: List<AshRpcError>
    ) : ValidationResult()
    """
  end

  @doc """
  Generates lifecycle hook type definitions if hooks are enabled.
  """
  def generate_hook_types do
    before_request = AshKotlinMultiplatform.rpc_action_before_request_hook()
    after_request = AshKotlinMultiplatform.rpc_action_after_request_hook()

    if before_request || after_request do
      """
      // Hook context types
      data class ActionHookContext(
          val action: String,
          val input: Map<String, Any?>? = null,
          val metadata: Map<String, Any?>? = null
      )
      """
    else
      ""
    end
  end
end
