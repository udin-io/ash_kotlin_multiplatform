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
    Pipeline.format_output(processed, request)
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
  alias AshKotlinMultiplatform.Rpc

  @doc """
  Builds the Kotlin-specific configuration map for the shared pipeline.
  """
  def build_config do
    %{
      input_field_formatter: Rpc.input_field_formatter(),
      output_field_formatter: Rpc.output_field_formatter(),
      field_names_callback: :interop_field_names,
      get_original_field_name: &get_original_field_name/2,
      format_field_for_client: &format_field_for_client/3,
      not_found_error?: AshKotlinMultiplatform.warn_on_missing_rpc_config?()
    }
  end

  @doc """
  Stage 2: Execute Ash action using the parsed request.

  Delegates to the shared pipeline with Kotlin configuration.
  """
  @spec execute_ash_action(Request.t()) :: {:ok, term()} | {:error, term()}
  def execute_ash_action(%Request{} = request) do
    SharedPipeline.execute_ash_action(request, build_config())
  end

  @doc """
  Stage 3: Process result with field extraction.

  Delegates to the shared pipeline with Kotlin configuration.
  """
  @spec process_result(term(), Request.t()) :: {:ok, term()} | {:error, term()}
  def process_result(ash_result, %Request{} = request) do
    SharedPipeline.process_result(ash_result, request, build_config())
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
  Stage 4: Format output with type awareness.

  Applies type-aware Kotlin field formatting.
  """
  @spec format_output(term(), Request.t()) :: term()
  def format_output(filtered_result, %Request{} = request) do
    SharedPipeline.format_output_with_request(filtered_result, request, build_config())
  end

  @doc """
  Formats a sort string by converting field names from client format to internal format.

  Delegates to the shared pipeline.
  """
  def format_sort_string(sort_string) do
    formatter = Rpc.input_field_formatter()
    SharedPipeline.format_sort_string(sort_string, formatter)
  end

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

  # Formats a field name for Kotlin client consumption
  defp format_field_for_client(field_name, resource, formatter) do
    # First check if resource has a custom field name mapping
    if resource do
      case get_kotlin_field_name(resource, field_name) do
        nil -> FieldFormatter.format_field_name(field_name, formatter)
        client_name -> client_name
      end
    else
      FieldFormatter.format_field_name(field_name, formatter)
    end
  end

  defp get_kotlin_field_name(resource, field_name) do
    case AshKotlinMultiplatform.Resource.Info.kotlin_field_names(resource) do
      field_names when is_list(field_names) ->
        Keyword.get(field_names, field_name)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
