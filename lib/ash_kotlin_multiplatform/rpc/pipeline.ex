# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Pipeline do
  @moduledoc """
  Kotlin-specific RPC pipeline wrapper.

  This module provides a Kotlin-configured wrapper around the shared
  `AshIntrospection.Rpc.Pipeline` module. It injects Kotlin-specific
  formatters and callbacks while delegating the core pipeline logic
  to the shared implementation.

  ## Usage

  ```elixir
  alias AshKotlinMultiplatform.Rpc.Pipeline

  # Execute the pipeline stages
  with {:ok, request} <- Pipeline.parse_request(otp_app, conn, params),
       {:ok, result} <- Pipeline.execute_ash_action(request),
       {:ok, processed} <- Pipeline.process_result(result, request) do
    Pipeline.format_data(processed, request)
  end
  ```

  ## Configuration

  The pipeline uses configuration from `AshKotlinMultiplatform`:
  - `input_field_formatter/0` - Formatter for incoming field names (default: :camel_case)
  - `output_field_formatter/0` - Formatter for outgoing field names (default: :camel_case)
  """

  alias AshIntrospection.FieldFormatter
  alias AshIntrospection.Rpc.Pipeline, as: SharedPipeline
  alias AshIntrospection.Rpc.Request
  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Manifest.Entrypoints
  alias AshKotlinMultiplatform.Rpc

  @doc """
  Builds the Kotlin-specific configuration map for the shared pipeline.

  `not_found_error?` is per-action — see `build_config/1`. This arity carries
  the shared default, `true`, and serves the field selector and the error
  builder, neither of which reads that key.

  **It carries no `:manifest`, and it must stay that way.**
  `AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest` calls this
  function to build the config it decorates the manifest WITH, while the
  manifest module is still compiling (`decorate_manifest.ex:66`). Reading
  `config :ash_kotlin_multiplatform, manifest:` there would ask the module
  being compiled for its own persisted state. The request path calls
  `request_config/0` and `request_config/1` instead, and they are the only
  functions here that name a manifest.
  """
  def build_config do
    %{
      input_field_formatter: Rpc.input_field_formatter(),
      output_field_formatter: Rpc.output_field_formatter(),
      field_names_callback: :interop_field_names,
      get_original_field_name: &get_original_field_name/2,
      format_field_for_client: &format_field_for_client/3,
      not_found_error?: true
    }
  end

  @doc """
  Builds the pipeline configuration for one RPC action.

  Only `not_found_error?` varies by action: it decides whether a `get?` read
  that matches no record is an `Ash.Error.Query.NotFound` or a successful
  `null`. It used to be wired to
  `AshKotlinMultiplatform.warn_on_missing_rpc_config?/0`, a codegen-time
  warning switch, so a project that silenced codegen warnings also turned every
  not-found into a null result.
  """
  def build_config(rpc_action) do
    Map.put(build_config(), :not_found_error?, Map.get(rpc_action, :not_found_error?, true))
  end

  @doc """
  `build_config/0` plus the compile-time manifest, for the request path.

  Every request entry point takes this rather than `build_config/0`, so
  `AshIntrospection.ResourceInfo` answers from the decorated
  `%Ash.Info.Manifest{}` the consumer's manifest module persisted instead of
  introspecting the resource live (`ash_introspection#23` stage 5a).

  Two keys, both required by the reader: `:manifest` is the bare persisted
  struct and `:manifest_namespace` names the `custom` key
  `AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest` wrote under.
  Without the namespace the reader looks under `:ash_introspection`, finds
  nothing and reads live — which is the bug `ash_introspection` 0.5.3 fixed in
  its own two config rebuilds.

  The manifest is handed over bare. Each entry point prepares it — four
  `AshIntrospection.ResourceInfo.normalize_config/1` calls per request, one per
  stage — rather than this library persisting a prepared
  `AshIntrospection.ResourceInfo.Source`. Measured cost is in
  [decisions.md](../../../docs/decisions.md); stage 5a's PR 6 revisits it.
  """
  @spec request_config() :: map()
  def request_config do
    Map.merge(build_config(), %{
      manifest: Manifest.manifest(),
      manifest_namespace: Entrypoints.namespace()
    })
  end

  @doc """
  `build_config/1` plus the compile-time manifest. See `request_config/0`.
  """
  @spec request_config(map()) :: map()
  def request_config(rpc_action) do
    Map.put(request_config(), :not_found_error?, Map.get(rpc_action, :not_found_error?, true))
  end

  @doc """
  Stage 2: Execute Ash action using the parsed request.

  Delegates to the shared pipeline with Kotlin configuration.
  """
  @spec execute_ash_action(Request.t()) :: {:ok, term()} | {:error, term()}
  def execute_ash_action(%Request{} = request) do
    SharedPipeline.execute_ash_action(request, request_config(request.rpc_action))
  end

  @doc """
  Stage 3: Process result with field extraction.

  Delegates to the shared pipeline with Kotlin configuration.
  """
  @spec process_result(term(), Request.t()) :: {:ok, term()} | {:error, term()}
  def process_result(ash_result, %Request{} = request) do
    SharedPipeline.process_result(ash_result, request, request_config())
  end

  @doc """
  Stage 4: Format output for client consumption.

  Applies Kotlin field formatting.
  """
  @spec format_output(term()) :: term()
  def format_output(filtered_result) do
    SharedPipeline.format_output(filtered_result, build_config())
  end

  @doc """
  Stage 4: Format one response payload by the Ash types the request names.

  Returns the payload alone. `AshKotlinMultiplatform.Rpc.Runner` wraps it in
  this library's `%{"success" => true, "data" => ...}` envelope, and that split
  is the whole reason this function exists rather than a direct call to
  `AshIntrospection.Rpc.Pipeline.format_output_with_request/3`.

  Two things separate the two. The shared function builds its own envelope, so
  calling it would duplicate `Runner.build_success_response/1`. And it hoists
  action metadata to a sibling of `data`, while this library nests it —
  `%{"data" => %{"data" => record, "metadata" => meta}}` — which is the shape
  #24 decided, `ClientServerContractTest` pins and the generated Kotlin decodes
  (`KotlinStatic.generate_generic_result_types/0` declares no top-level
  `metadata`). Measured 2026-09-11: routing stage 4 straight through the shared
  function failed seven tests, all of them that hoist.

  So the mutation-metadata shape stage 3 produces, `%{data: ..., metadata: ...}`,
  is matched here and recursed into. Metadata values are already formatted by
  type in stage 3 (`Pipeline.extract_metadata_fields/4`), so only their names
  are formatted here, once.

  Unlike `format_output/1` this formats **values** as well as names: it is what
  turns `%Ash.Vector{}` into `[0.25, -1.5, 3.0]` rather than shipping the packed
  binary `Jason` refuses (#71).
  """
  @spec format_data(term(), Request.t()) :: term()
  def format_data(%{data: data, metadata: metadata}, %Request{} = request) do
    %{
      envelope_key("data") => format_data(data, request),
      envelope_key("metadata") => format_output(metadata)
    }
  end

  def format_data(payload, %Request{} = request) do
    # The shared function is the only public entry point to type-aware
    # formatting, and it always wraps. Unwrapping its envelope costs one
    # `Map.fetch!/2` and keeps this library off a private API.
    %{success: true, data: payload}
    |> SharedPipeline.format_output_with_request(request, request_config())
    |> Map.fetch!(envelope_key("data"))
  end

  @doc """
  Formats a sort string by converting field names from client format to internal format.

  Delegates to the shared pipeline.
  """
  def format_sort_string(sort_string) do
    formatter = Rpc.input_field_formatter()
    SharedPipeline.format_sort_string(sort_string, formatter)
  end

  # The envelope's own keys go through the output formatter like any other
  # field name, so a project running `output_field_formatter :snake_case` gets
  # the same key here that `Runner.build_success_response/1` writes.
  defp envelope_key(name),
    do: FieldFormatter.format_field_name(name, Rpc.output_field_formatter())

  # ---------------------------------------------------------------------------
  # Kotlin-specific callbacks
  # ---------------------------------------------------------------------------

  # Gets the original field name from a Kotlin resource
  defp get_original_field_name(resource, client_key) do
    case AshKotlinMultiplatform.Resource.Info.get_original_field_name(resource, client_key) do
      nil -> nil
      name when is_atom(name) -> name
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # The wire name for one field. `Resource.Info.client_field_name/3` is the
  # single answer codegen also asks, so the key written here and the key the
  # generated Kotlin reads cannot drift apart. This used to keep its own copy of
  # the lookup and returned the DSL's atom verbatim, which put an atom key in a
  # payload of string keys (#71).
  defp format_field_for_client(field_name, nil, formatter) do
    FieldFormatter.format_field_name(field_name, formatter)
  end

  defp format_field_for_client(field_name, resource, formatter) do
    AshKotlinMultiplatform.Resource.Info.client_field_name(resource, field_name, formatter)
  rescue
    _ -> FieldFormatter.format_field_name(field_name, formatter)
  end
end
