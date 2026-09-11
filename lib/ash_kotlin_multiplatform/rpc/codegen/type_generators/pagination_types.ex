# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.PaginationTypes do
  @moduledoc """
  Generates the one Kotlin type every paginated read returns.

  A read that supports pagination answers with two different JSON shapes, and
  which one it sends is decided by the request, not by the action:
  `AshIntrospection.Rpc.ResultProcessor.process/4` returns a bare list when the
  request carried no `page`, and a page object (`results`, `hasMore`, `limit`,
  `offset` or the keyset cursors, `count`, `type`) when it did. Ash 3 defaults
  every read to `offset? true, keyset? true, required? false`
  (`Ash.Resource.Info.action(resource, :read).pagination`), so "supports
  pagination" is true for almost every read a consumer exposes, and a generated
  function cannot know at compile time which shape it will receive.

  So there is one type, `AshPage<T>`, and a hand-written serializer that reads
  both shapes into it. That is what lets `listTodos()` declare a return type at
  all. Until #22 this module emitted a `{Action}OffsetResult` /
  `{Action}KeysetResult` / `{Action}PaginatedResult` family per action, none of
  which was ever referenced by a generated function, and none of which could
  have decoded the un-paginated call.
  """

  alias AshIntrospection.Codegen.ActionIntrospection

  @doc """
  Generates `AshPage<T>` and its serializer.

  Static: the same Kotlin for every application, emitted once per file.

  Every field but `results` is nullable or defaulted, because the server omits
  or nulls them freely — `count` is `null` unless the request asked for it, and
  the keyset cursors are `null` on an empty page
  (`AshIntrospection.Rpc.ResultProcessor.process/4`). The `type` discriminator
  the server sends (`"offset"` or `"keyset"`) is deliberately not a field: it
  says which pagination Ash applied, which the caller can already tell from
  which cursors came back.
  """
  def generate_page_type do
    """
    // What a read returns. The server sends a bare JSON array when the request
    // carried no `page` and a page object when it did, so this one type reads
    // both and `results` is always populated.
    @Serializable(with = AshPageSerializer::class)
    data class AshPage<T>(
        val results: List<T>,
        val hasMore: Boolean = false,
        val limit: Int? = null,
        val offset: Int? = null,
        val count: Int? = null,
        val after: String? = null,
        val before: String? = null,
        val previousPage: String? = null,
        val nextPage: String? = null
    )

    // A generic class annotated `@Serializable(with = ...)` resolves through a
    // serializer constructed with one KSerializer per type parameter, which is
    // why this takes `element`:
    // https://kotlinlang.org/docs/serialization-custom-serializers.html
    class AshPageSerializer<T>(private val element: KSerializer<T>) : KSerializer<AshPage<T>> {
        override val descriptor: SerialDescriptor =
            buildClassSerialDescriptor("AshPage", element.descriptor)

        override fun deserialize(decoder: Decoder): AshPage<T> {
            val input = decoder as? JsonDecoder
                ?: throw SerializationException("AshPage decodes from JSON only")

            return when (val json = input.decodeJsonElement()) {
                is JsonArray -> AshPage(results = decodeResults(input, json))

                is JsonObject -> AshPage(
                    results = json["results"]?.let { decodeResults(input, it) } ?: emptyList(),
                    hasMore = json["hasMore"]?.jsonPrimitive?.booleanOrNull ?: false,
                    limit = json["limit"]?.jsonPrimitive?.intOrNull,
                    offset = json["offset"]?.jsonPrimitive?.intOrNull,
                    count = json["count"]?.jsonPrimitive?.intOrNull,
                    after = json["after"]?.jsonPrimitive?.contentOrNull,
                    before = json["before"]?.jsonPrimitive?.contentOrNull,
                    previousPage = json["previousPage"]?.jsonPrimitive?.contentOrNull,
                    nextPage = json["nextPage"]?.jsonPrimitive?.contentOrNull
                )

                else -> throw SerializationException(
                    "expected a list or a page object, got $json"
                )
            }
        }

        override fun serialize(encoder: Encoder, value: AshPage<T>) {
            val output = encoder as? JsonEncoder
                ?: throw SerializationException("AshPage encodes to JSON only")

            output.encodeJsonElement(buildJsonObject {
                put("results", output.json.encodeToJsonElement(ListSerializer(element), value.results))
                put("hasMore", value.hasMore)
                value.limit?.let { put("limit", it) }
                value.offset?.let { put("offset", it) }
                value.count?.let { put("count", it) }
                value.after?.let { put("after", it) }
                value.before?.let { put("before", it) }
                value.previousPage?.let { put("previousPage", it) }
                value.nextPage?.let { put("nextPage", it) }
            })
        }

        private fun decodeResults(input: JsonDecoder, json: JsonElement): List<T> =
            if (json is JsonNull) {
                emptyList()
            } else {
                input.json.decodeFromJsonElement(ListSerializer(element), json)
            }
    }
    """
  end

  @doc """
  Generates pagination config types for request configuration.
  """
  def generate_pagination_config_types do
    """
    // Pagination config types
    @Serializable
    data class OffsetPaginationConfig(
        val limit: Int? = null,
        val offset: Int? = null,
        val count: Boolean = false
    )

    @Serializable
    data class KeysetPaginationConfig(
        val limit: Int? = null,
        val after: String? = null,
        val before: String? = null,
        val count: Boolean = false
    )
    """
  end

  @doc """
  Checks if an action supports any form of pagination.
  """
  def action_supports_pagination?(action) do
    ActionIntrospection.action_supports_pagination?(action)
  end

  @doc """
  Checks if an action requires pagination (not optional).
  """
  def action_requires_pagination?(action) do
    ActionIntrospection.action_requires_pagination?(action)
  end
end
