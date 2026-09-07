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
        :kotlinx_datetime ->
          """
          import kotlinx.datetime.*
          import kotlinx.serialization.KSerializer
          import kotlinx.serialization.descriptors.PrimitiveKind
          import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
          import kotlinx.serialization.descriptors.SerialDescriptor
          import kotlinx.serialization.encoding.Decoder
          import kotlinx.serialization.encoding.Encoder
          import kotlinx.serialization.modules.SerializersModule
          import kotlinx.serialization.modules.contextual
          """
          |> String.trim_trailing()

        :java_time ->
          "import java.time.*"
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
    # kotlinx-datetime 0.7 removed the concrete InstantIso8601Serializer object (Instant is
    # deprecated in favor of kotlin.time.Instant there) in favor of an abstract
    # FormattedInstantSerializer base that doesn't exist before 0.7. Neither name is safe to
    # reference unconditionally — this codegen has no way to know which kotlinx-datetime
    # version a given consumer has pinned — so this hand-writes a KSerializer against only
    # Instant.toString()/Instant.parse(), which are stable ISO-8601 API across that version
    # split. Fields typed as Instant are emitted as @Contextual (see
    # ResourceSchemas.generate_field/1) and resolved through the SerializersModule below at
    # runtime.
    {instant_serializer_decl, serializers_module} =
      case AshKotlinMultiplatform.datetime_library() do
        :kotlinx_datetime ->
          decl = """
          private object InstantIso8601Serializer : KSerializer<kotlinx.datetime.Instant> {
              override val descriptor: SerialDescriptor =
                  PrimitiveSerialDescriptor("kotlinx.datetime.Instant", PrimitiveKind.STRING)

              override fun serialize(encoder: Encoder, value: kotlinx.datetime.Instant) {
                  encoder.encodeString(value.toString())
              }

              override fun deserialize(decoder: Decoder): kotlinx.datetime.Instant {
                  return kotlinx.datetime.Instant.parse(decoder.decodeString())
              }
          }

          """

          {decl,
           "\n                    serializersModule = SerializersModule { contextual(InstantIso8601Serializer) }"}

        :java_time ->
          {"", ""}
      end

    """
    #{instant_serializer_decl}// HTTP Client factory
    fun createHttpClient(): HttpClient {
        return HttpClient {
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true#{serializers_module}
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
