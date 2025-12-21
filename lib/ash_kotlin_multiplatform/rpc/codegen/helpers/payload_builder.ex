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
        payload_lines ++ ["put(\"identity\", Json.encodeToJsonElement(config.identity))"]
      else
        payload_lines
      end

    # Add input if needed
    payload_lines =
      case context.action_input_type do
        :required ->
          payload_lines ++ ["put(\"input\", Json.encodeToJsonElement(config.input))"]

        :optional ->
          payload_lines ++ ["config.input?.let { put(\"input\", Json.encodeToJsonElement(it)) }"]

        :none ->
          payload_lines
      end

    # Add fields if included
    payload_lines =
      if include_fields do
        payload_lines ++
          [
            """
            putJsonArray("fields") {
                            config.fields.forEach { field ->
                                when (field) {
                                    is String -> add(field)
                                    else -> add(Json.encodeToJsonElement(field))
                                }
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
          [
            "config.filter?.let { put(\"filter\", Json.encodeToJsonElement(it)) }",
            "config.sort?.let { put(\"sort\", it) }"
          ]
      else
        payload_lines
      end

    # Add pagination if supported
    payload_lines =
      if context.supports_pagination do
        payload_lines ++ ["config.page?.let { put(\"page\", Json.encodeToJsonElement(it)) }"]
      else
        payload_lines
      end

    # Add metadata fields if included
    payload_lines =
      if include_metadata_fields do
        payload_lines ++
          ["config.metadataFields?.let { put(\"metadataFields\", Json.encodeToJsonElement(it)) }"]
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
          payload_lines ++ ["put(\"input\", Json.encodeToJsonElement(config.input))"]

        :optional ->
          payload_lines ++ ["config.input?.let { put(\"input\", Json.encodeToJsonElement(it)) }"]

        :none ->
          payload_lines
      end

    Enum.join(payload_lines, "\n                ")
  end
end
