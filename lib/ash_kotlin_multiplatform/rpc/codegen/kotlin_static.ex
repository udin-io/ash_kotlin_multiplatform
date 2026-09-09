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
  def generate_imports(_opts \\ []) do
    # Both settings hand-write KSerializers, so both need the serialization
    # plumbing that declares and registers them.
    datetime_package =
      case AshKotlinMultiplatform.datetime_library() do
        :kotlinx_datetime -> "import kotlinx.datetime.*"
        :java_time -> "import java.time.*"
      end

    datetime_imports =
      """
      #{datetime_package}
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
    #{websocket_imports}
    """
    |> String.trim()
  end

  @doc """
  Generates a helper function to create a configured HttpClient.
  """
  def generate_http_client_factory do
    {serializer_decls, serializers_module} =
      case AshKotlinMultiplatform.datetime_library() do
        :kotlinx_datetime -> kotlinx_datetime_serializers()
        :java_time -> java_time_serializers()
      end

    """
    #{serializer_decls}// HTTP Client factory
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

  # kotlinx-datetime 0.7 removed the concrete InstantIso8601Serializer object (Instant is
  # deprecated in favor of kotlin.time.Instant there) in favor of an abstract
  # FormattedInstantSerializer base that doesn't exist before 0.7. Neither name is safe to
  # reference unconditionally — this codegen has no way to know which kotlinx-datetime
  # version a given consumer has pinned — so this hand-writes a KSerializer against only
  # Instant.toString()/Instant.parse(), which are stable ISO-8601 API across that version
  # split. Fields typed as Instant are emitted as @Contextual (see
  # ResourceSchemas.generate_field/1) and resolved through the SerializersModule at runtime.
  #
  # The other kotlinx-datetime types keep their built-in serializers, so they need
  # neither a declaration here nor the annotation.
  defp kotlinx_datetime_serializers do
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
     "\n                serializersModule = SerializersModule { contextual(InstantIso8601Serializer) }"}
  end

  # kotlinx-serialization ships a serializer for no java.time type, so every date or
  # time field under `datetime_library: :java_time` was a SERIALIZER_NOT_FOUND compile
  # error (#45). Annotating the fields `@Contextual` alone would only move the failure
  # to decode time, so each type also gets a serializer registered here.
  #
  # ISO-8601 both ways, which is what an Ash JSON API sends and accepts. Every type
  # below round-trips through `toString()`/`parse()` on that format — except
  # ZonedDateTime, whose `toString()` appends the region in brackets
  # ("2026-01-01T00:00Z[Europe/Paris]"), which Ash's datetime parser rejects. It is
  # written with ISO_OFFSET_DATE_TIME instead; `ZonedDateTime.parse` reads both forms.
  defp java_time_serializers do
    types = AshKotlinMultiplatform.Codegen.TypeMapper.java_time_contextual_types()

    decls =
      types
      |> Enum.map_join("\n", &java_time_serializer_declaration/1)
      |> Kernel.<>("\n")

    registrations =
      Enum.map_join(types, "\n", fn type ->
        "                    contextual(#{java_time_serializer_name(type)})"
      end)

    module =
      "\n                serializersModule = SerializersModule {\n" <>
        registrations <> "\n                }"

    {decls, module}
  end

  defp java_time_serializer_declaration(type) do
    """
    private object #{java_time_serializer_name(type)} : KSerializer<#{type}> {
        override val descriptor: SerialDescriptor =
            PrimitiveSerialDescriptor("#{type}", PrimitiveKind.STRING)

        override fun serialize(encoder: Encoder, value: #{type}) {
            encoder.encodeString(#{java_time_encoded_value(type)})
        }

        override fun deserialize(decoder: Decoder): #{type} {
            return #{type}.parse(decoder.decodeString())
        }
    }
    """
  end

  defp java_time_serializer_name(type) do
    "Java" <> String.replace_prefix(type, "java.time.", "") <> "Iso8601Serializer"
  end

  defp java_time_encoded_value("java.time.ZonedDateTime"),
    do: "java.time.format.DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(value)"

  defp java_time_encoded_value(_type), do: "value.toString()"

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
  # `shortMessage` carries no `@SerialName`. Every error map `Rpc.Runner` builds
  # writes the key `"shortMessage"` literally, under every
  # `output_field_formatter` setting: see `build_error_response/1`,
  # `format_validation_errors/1` and `format_single_error/1`. Annotating the
  # field `short_message` therefore made it decode as `null` on every error the
  # server has ever sent (#24).
  def generate_error_types do
    """
    // RPC Error types
    @Serializable
    data class AshRpcError(
        val type: String? = null,
        val message: String? = null,
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
