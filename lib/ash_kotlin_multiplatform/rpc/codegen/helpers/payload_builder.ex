# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.Helpers.PayloadBuilder do
  @moduledoc """
  Builds RPC request payload structures for Kotlin code generation.

  This module generates the payload construction code that will be used
  in the generated Kotlin RPC functions to send requests to the server.
  """

  @doc """
  The Kotlin source of a function that turns one `fields` element into a
  `JsonElement` by an explicit `when` over its runtime type, instead of
  asking kotlinx-serialization to resolve a serializer for `Any` (#62).

  Embedded once per generated action as a local function
  (`build_payload_code/3`), or once at file scope, prefixed `internal`, by
  `PhoenixChannel.generate_rpc_channel/0` — both from this one Elixir source
  so the two copies never drift apart. `visibility` is `""` for a local
  declaration (Kotlin forbids a visibility modifier there) or `"internal "`
  for the file-scope one.
  """
  def field_to_json_element_source(visibility \\ "") do
    """
    #{visibility}fun ashFieldToJsonElement(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is String -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        is Map<*, *> -> JsonObject(
            value.entries.associate { (k, v) ->
                k.toString() to ashFieldToJsonElement(v)
            }
        )
        is List<*> -> JsonArray(value.map { ashFieldToJsonElement(it) })
        else -> throw IllegalArgumentException(
            "Cannot encode field selection element of type " +
                "${value::class.simpleName}"
        )
    }
    """
    |> String.trim()
  end

  @doc """
  Generates the payload construction code for an RPC function.

  ## Parameters

    * `rpc_action_name` - The name of the RPC action
    * `context` - The action context from ConfigBuilder
    * `opts` - Options keyword list:
      - `:include_fields` - Whether to include the fields parameter
      - `:include_metadata_fields` - Whether to include metadata_fields parameter

  ## Returns

  A string containing Kotlin code for building the request payload.
  """
  def build_payload_code(rpc_action_name, context, opts \\ []) do
    include_fields = Keyword.get(opts, :include_fields, true)
    include_metadata_fields = Keyword.get(opts, :include_metadata_fields, false)

    payload_lines = [
      "put(\"action\", \"#{rpc_action_name}\")"
    ]

    # Add tenant if required
    payload_lines =
      if context.requires_tenant do
        payload_lines ++ ["put(\"tenant\", config.tenant)"]
      else
        payload_lines
      end

    # Add identity if present
    payload_lines =
      if context.identities != [] do
        payload_lines ++ ["put(\"identity\", ashRpcJson.encodeToJsonElement(config.identity))"]
      else
        payload_lines
      end

    # Add the get_by lookup for a single-record read
    payload_lines =
      if context.get_by != [] do
        payload_lines ++ ["put(\"getBy\", ashRpcJson.encodeToJsonElement(config.getBy))"]
      else
        payload_lines
      end

    # Add input if needed
    payload_lines =
      case context.action_input_type do
        :required ->
          payload_lines ++ ["put(\"input\", ashRpcJson.encodeToJsonElement(config.input))"]

        :optional ->
          payload_lines ++
            ["config.input?.let { put(\"input\", ashRpcJson.encodeToJsonElement(it)) }"]

        :none ->
          payload_lines
      end

    # Add fields if included
    payload_lines =
      if include_fields do
        payload_lines ++
          [
            field_to_json_element_source(),
            """
            putJsonArray("fields") {
                            config.fields.forEach { field ->
                                add(ashFieldToJsonElement(field))
                            }
                        }
            """
            |> String.trim()
          ]
      else
        payload_lines
      end

    # Add filter if supported
    payload_lines =
      if context.supports_filtering do
        payload_lines ++
          ["config.filter?.let { put(\"filter\", ashRpcJson.encodeToJsonElement(it)) }"]
      else
        payload_lines
      end

    # Add sort if supported
    payload_lines =
      if context.supports_sorting do
        payload_lines ++ ["config.sort?.let { put(\"sort\", it) }"]
      else
        payload_lines
      end

    # Add pagination if supported
    payload_lines =
      if context.supports_pagination do
        payload_lines ++
          ["config.page?.let { put(\"page\", ashRpcJson.encodeToJsonElement(it)) }"]
      else
        payload_lines
      end

    # Add metadata fields if included
    payload_lines =
      if include_metadata_fields do
        payload_lines ++
          [
            "config.metadataFields?.let { put(\"metadataFields\", ashRpcJson.encodeToJsonElement(it)) }"
          ]
      else
        payload_lines
      end

    Enum.join(payload_lines, "\n                ")
  end

  @doc """
  Generates the payload for a validation request.
  """
  def build_validation_payload_code(rpc_action_name, context) do
    payload_lines = [
      "put(\"action\", \"#{rpc_action_name}\")"
    ]

    # Add tenant if required
    payload_lines =
      if context.requires_tenant do
        payload_lines ++ ["put(\"tenant\", config.tenant)"]
      else
        payload_lines
      end

    # Add input if needed
    payload_lines =
      case context.action_input_type do
        :required ->
          payload_lines ++ ["put(\"input\", ashRpcJson.encodeToJsonElement(config.input))"]

        :optional ->
          payload_lines ++
            ["config.input?.let { put(\"input\", ashRpcJson.encodeToJsonElement(it)) }"]

        :none ->
          payload_lines
      end

    Enum.join(payload_lines, "\n                ")
  end
end
