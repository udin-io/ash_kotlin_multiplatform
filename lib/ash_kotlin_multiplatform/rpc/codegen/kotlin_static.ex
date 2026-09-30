# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic do
  @moduledoc """
  Generates static Kotlin code components that are included in every generated file.

  This includes imports, utility types, error types, and helper functions.
  """

  # #33 row 19 (owner, 2026-09-30): a generated top-level class shadowing
  # one of these breaks the consumer's build — Kotlin resolves a local
  # declaration over a star import with no ambiguity error, so every bare
  # use of the shadowed name silently binds to the wrong class instead.
  # Confirmed for real with `gradle compileKotlin`: a fixture-local
  # `class Json`/`class Serializable`/`class ContentType` (etc.) each threw
  # `INITIALIZER_TYPE_MISMATCH`, `NOT_AN_ANNOTATION_CLASS` or a cascade of
  # `Unresolved reference` at every real use site.
  #
  # Each name here was found by grepping the real generated fixture for a
  # BARE (unqualified) use of it — never guessed from the package's public
  # API, and never added just because the package is star-imported. Confirmed
  # empty for `kotlinx.datetime`/`java.time` and every websocket/coroutines
  # import: this generator always qualifies those (`kotlinx.datetime.Instant`,
  # never bare `Instant`), so a resource typed `Instant` shadows nothing real
  # today — flagged as a question on the PR, since the owner's decision named
  # it as an example before this was checked.
  @reserved_names_by_package %{
    "kotlinx.serialization" => ["Serializable", "SerialName", "Contextual"],
    "kotlinx.serialization.json" => ["Json"],
    "io.ktor.client" => ["HttpClient"],
    "io.ktor.http" => ["ContentType"],
    "io.ktor.client.plugins.contentnegotiation" => ["ContentNegotiation"]
  }

  @doc """
  `{source, fragment}` pairs for every top-level name this generator itself
  references unqualified from a star-imported package, for
  `Codegen.Declarations.check/1`.

  The package list comes from parsing `generate_imports/1`'s own output for
  the run's options, not a fixed list disconnected from what is actually
  imported — an import this run does not emit contributes no reserved name.
  """
  def reserved_top_level_names(opts \\ []) do
    opts
    |> generate_imports()
    |> String.split("\n")
    |> Enum.flat_map(&star_import_package/1)
    |> Enum.flat_map(fn package ->
      @reserved_names_by_package
      |> Map.get(package, [])
      |> Enum.map(fn name ->
        {"built-in (star import #{package}.*, used unqualified as #{name})", "class #{name}"}
      end)
    end)
  end

  defp star_import_package(line) do
    case Regex.run(~r/\Aimport\s+([\w.]+)\.\*\z/, String.trim(line)) do
      [_, package] -> [package]
      nil -> []
    end
  end

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
      import kotlinx.serialization.builtins.ListSerializer
      import kotlinx.serialization.descriptors.PrimitiveKind
      import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
      import kotlinx.serialization.descriptors.SerialDescriptor
      import kotlinx.serialization.descriptors.buildClassSerialDescriptor
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
  Generates the hand-written serializers and the one `Json` that carries them.

  Every encode and decode path in the emitted file goes through `ashRpcJson`.
  Before #54 four did not: `createHttpClient()` registered the
  `SerializersModule`, while `RpcResult.dataAs()` and the Phoenix channel client
  each built a `Json` of their own and every request payload encoded through the
  `Json` companion — which is `Json.Default`, and carries no module. A
  `@Contextual` field down any of those paths threw
  `SerializationException: Serializer for class '...' is not found` at runtime,
  on code the compiler had no complaint about.

  `ashRpcJson` is public so consumers can decode with the same configuration the
  client uses, and because `dataAs()` is `inline` — an inline function body can
  only reach public declarations.

  The settings are `createHttpClient()`'s. The channel client also set
  `encodeDefaults = true`, which is deliberately not carried over: it changes
  what `encodeToJsonElement` writes for a `@Serializable` class, the channel
  client encodes none (it hands the encoder `Map<String, JsonPrimitive>` and
  `JsonElement`), and turning it on for the HTTP payloads would start sending
  every unset input field as an explicit `null` — which Ash reads as "set this
  attribute to nil", not as "leave it alone".
  """
  def generate_shared_json do
    {serializer_decls, serializers_module} =
      case AshKotlinMultiplatform.datetime_library() do
        :kotlinx_datetime -> kotlinx_datetime_serializers()
        :java_time -> java_time_serializers()
      end

    """
    #{serializer_decls}// The one Json every generated encode and decode path uses. Public so a
    // consumer decodes with the same configuration the client does (#54).
    val ashRpcJson: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true#{serializers_module}
    }
    """
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
                json(ashRpcJson)
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

    {decl, "\n    serializersModule = SerializersModule { contextual(InstantIso8601Serializer) }"}
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
        "        contextual(#{java_time_serializer_name(type)})"
      end)

    module = "\n    serializersModule = SerializersModule {\n" <> registrations <> "\n    }"

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
  Generates the shared class a money value decodes into.

  `AshKotlinMultiplatform.Codegen.TypeMapper` types `AshMoney.Types.Money` as
  `AshMoney`, and a field typed `AshMoney` in a file that declares no such class
  does not compile — so the mapping and this declaration are one decision (#30).

  Emitted for every application, like the type aliases above, because the
  generator cannot tell whether a consumer's resources use money without
  ash_money as a dependency, and an unused class costs a consumer nothing.

  The two fields are what ash_money puts on the wire: its `Jason.Encoder` sends
  `currency` and `amount` and nothing else, and `AshMoney.Types.Money`'s
  `json_schema/1` documents both as strings. `amount` is a `String` for the
  reason `Ash.Type.Decimal` is one — `Decimal`'s JSON encoder writes a quoted
  decimal string, and reading it into a `Double` would round a currency amount.
  """
  def generate_money_type do
    """
    // A money value, as ash_money sends it: a decimal string and a currency
    // code (#30).
    @Serializable
    data class AshMoney(
        val amount: String,
        val currency: String
    )
    """
  end

  @doc """
  Generates the RPC error types.
  """
  # `Rpc.Runner.to_client/1` now spells every error key with
  # `output_field_formatter` (#57), the same as a success response's `data`
  # keys. `shortMessage` and `errorId` are the only two properties whose
  # wire name changes under `:snake_case` (`short_message`, `error_id`), so
  # `@SerialName` is emitted exactly there, mirroring
  # `ResourceSchemas.property_name/2`. Under the default `:camel_case` every
  # wire name already equals the property name, so no `@SerialName` is
  # emitted and this generates the same source as before (#24).
  def generate_error_types do
    formatter = AshKotlinMultiplatform.Rpc.output_field_formatter()

    properties = [
      {"type", "type", "String? = null"},
      {"message", "message", "String? = null"},
      {"short_message", "shortMessage", "String? = null"},
      {"vars", "vars", "Map<String, JsonElement> = emptyMap()"},
      {"field", "field", "String? = null"},
      {"fields", "fields", "List<String> = emptyList()"},
      {"path", "path", "List<String> = emptyList()"},
      {"details", "details", "Map<String, JsonElement>? = null"},
      {"error_id", "errorId", "String? = null"}
    ]

    lines =
      Enum.map(properties, fn {canonical, property, type} ->
        wire_name = AshIntrospection.FieldFormatter.format_field_name(canonical, formatter)
        prefix = if wire_name == property, do: "", else: "@SerialName(\"#{wire_name}\")\n    "
        "    #{prefix}val #{property}: #{type}"
      end)

    """
    // RPC Error types
    @Serializable
    data class AshRpcError(
    #{Enum.join(lines, ",\n")}
    )
    """
  end

  @doc """
  Generates the result wrapper every generated RPC function returns.

  `RpcResult` is generic over what the action returns, so `createTodo()` returns
  `RpcResult<Todo>` and `listTodos()` returns `RpcResult<AshPage<Todo>>` and
  `result.data` is already the type the caller wanted. Until #22 it was
  `RpcResult` with `data: JsonElement?`, identical for all fifteen actions, and
  the caller named the type by hand through `dataAs<T>()` — which the README
  has always described as end-to-end type safety. The Swift generator has
  emitted `RpcResult<T: Codable>` since it was written
  (`AshKotlinMultiplatform.Swift.Codegen.generate_result_types/0`); this is the
  Kotlin side catching up.

  `dataAs()` survives as an extension on `RpcResult<JsonElement>`, which is what
  the Phoenix channel client returns: it takes the action name as a string, so
  it has no type to name.
  """
  # No `metadata` property. `Rpc.Runner.build_success_response/1` returns
  # `success` and `data` and nothing else, and action metadata reaches the
  # client *inside* `data` — `AshIntrospection.Rpc.Pipeline.add_metadata/4`
  # merges the exposed fields into the record. A top-level `metadata` promised a
  # key the server has never sent, so it decoded as `null` every time and sent
  # readers looking for it in the wrong place (#24).
  def generate_generic_result_types do
    """
    // Generic result wrapper, typed on what its action returns (#22).
    @Serializable
    data class RpcResult<T>(
        val success: Boolean,
        val data: T? = null,
        val errors: List<AshRpcError>? = null
    ) {
        fun isSuccess(): Boolean = success
        fun isError(): Boolean = !success
    }

    // For an untyped result — the channel client's, or one decoded by hand.
    // Through `ashRpcJson`, not a fresh Json: a date or an untyped map here is
    // the primary happy path, and its own Json carried no serializers (#54).
    inline fun <reified T> RpcResult<JsonElement>.dataAs(): T? {
        return data?.let { ashRpcJson.decodeFromJsonElement<T>(it) }
    }
    """
  end

  @doc """
  Generates the validation result type.
  """
  # A plain `@Serializable sealed class` makes kotlinx-serialization look for a
  # `"type"` class discriminator. `Rpc.Runner.build_validation_success_response/0`
  # sends `{"success":true,"valid":true}` and
  # `build_validation_error_response/1` sends the same with `"valid":false` and
  # an `"errors"` list — neither carries a discriminator, so every `validateX()`
  # call threw `JsonDecodingException` on decode (#24).
  #
  # `valid` is the discriminator the server already sends, and
  # `JsonContentPolymorphicSerializer` is how kotlinx reads one out of the
  # content rather than out of a synthetic key:
  # https://kotlinlang.org/api/kotlinx.serialization/kotlinx-serialization-json/kotlinx.serialization.json/-json-content-polymorphic-serializer/
  # Choosing it over adding `"type"` to the response keeps the wire format the
  # Swift generator and the Phoenix channel client already read unchanged.
  def generate_validation_types do
    """
    // Validation result types
    @Serializable(with = ValidationResultSerializer::class)
    sealed class ValidationResult {
        abstract val valid: Boolean
    }

    // The server sends no class discriminator, so the `valid` flag is the
    // discriminator. See AshKotlinMultiplatform.Rpc.Runner.
    object ValidationResultSerializer :
        JsonContentPolymorphicSerializer<ValidationResult>(ValidationResult::class) {
        override fun selectDeserializer(
            element: JsonElement
        ): DeserializationStrategy<ValidationResult> =
            if (element.jsonObject["valid"]?.jsonPrimitive?.booleanOrNull == true) {
                ValidationValid.serializer()
            } else {
                ValidationInvalid.serializer()
            }
    }

    @Serializable
    data class ValidationValid(
        override val valid: Boolean = true
    ) : ValidationResult()

    @Serializable
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
