# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform do
  @moduledoc """
  Generate type-safe Kotlin Multiplatform clients from your Ash resources.

  AshKotlinMultiplatform provides:
  - Automatic generation of Kotlin data classes from Ash resources
  - Type-safe RPC functions using Ktor client
  - Phoenix Channel support for real-time features
  - kotlinx.serialization integration

  ## Quick Start

  1. Add AshKotlinMultiplatform to your dependencies
  2. Add `AshKotlinMultiplatform.Resource` extension to your resources
  3. Add `AshKotlinMultiplatform.Rpc` extension to your domain
  4. Run `mix ash_kotlin_multiplatform.codegen`

  ## DSL Extensions

  - `AshKotlinMultiplatform.Resource` - Configure resource-level Kotlin options
  - `AshKotlinMultiplatform.Rpc` - Configure domain-level RPC options

  ## Generated Output

  The codegen produces:
  - Kotlin data classes with @Serializable annotations
  - Suspend functions for HTTP RPC calls using Ktor
  - Object-oriented API wrappers (e.g., TodoRpc.create())
  - Phoenix Channel client for WebSocket support
  """

  @doc """
  Returns the configured type mapping overrides.

  These allow mapping custom Ash types to specific Kotlin types.
  """
  def type_mapping_overrides do
    Application.get_env(:ash_kotlin_multiplatform, :type_mapping_overrides, [])
  end

  @doc """
  Returns the Kotlin type to use for untyped maps.

  Defaults to "Map<String, Any?>".
  """
  def untyped_map_type do
    Application.get_env(:ash_kotlin_multiplatform, :untyped_map_type, "Map<String, Any?>")
  end

  @doc """
  Returns the input field formatter (client → server).

  Defaults to :camel_case.
  """
  def input_field_formatter do
    Application.get_env(:ash_kotlin_multiplatform, :input_field_formatter, :camel_case)
  end

  @doc """
  Returns the output field formatter (server → client).

  Defaults to :camel_case.
  """
  def output_field_formatter do
    Application.get_env(:ash_kotlin_multiplatform, :output_field_formatter, :camel_case)
  end

  @doc """
  Returns whether to generate Phoenix Channel client functions.

  Defaults to true.
  """
  def generate_phoenix_channel_client? do
    Application.get_env(:ash_kotlin_multiplatform, :generate_phoenix_channel_client, true)
  end

  @doc """
  Returns whether to generate validation functions.

  Defaults to true.
  """
  def generate_validation_functions? do
    Application.get_env(:ash_kotlin_multiplatform, :generate_validation_functions, true)
  end

  @doc """
  Returns the default package name for generated Kotlin code.

  If not configured, will be auto-generated from the otp_app name.
  """
  def default_package_name do
    Application.get_env(:ash_kotlin_multiplatform, :package_name, nil)
  end

  @doc """
  Returns the nullable strategy for Kotlin types.

  - :explicit - Use explicit nullable types (String?, Int?)
  - :platform - Use platform types (String!, Int!)

  Defaults to :explicit.
  """
  def nullable_strategy do
    Application.get_env(:ash_kotlin_multiplatform, :nullable_strategy, :explicit)
  end

  @doc """
  Returns the datetime library to use for date/time types.

  - :kotlinx_datetime - kotlinx-datetime library (default)
  - :java_time - java.time classes (JVM only)

  Defaults to :kotlinx_datetime.
  """
  def datetime_library do
    Application.get_env(:ash_kotlin_multiplatform, :datetime_library, :kotlinx_datetime)
  end

  @doc """
  Returns the RPC run endpoint path.

  Defaults to "/rpc/run".
  """
  def run_endpoint do
    Application.get_env(:ash_kotlin_multiplatform, :run_endpoint, "/rpc/run")
  end

  @doc """
  Returns the RPC validate endpoint path.

  Defaults to "/rpc/validate".
  """
  def validate_endpoint do
    Application.get_env(:ash_kotlin_multiplatform, :validate_endpoint, "/rpc/validate")
  end

  @doc """
  Returns the output file path for generated Kotlin code.

  Defaults to "lib/generated/AshRpc.kt".
  """
  def output_file do
    Application.get_env(:ash_kotlin_multiplatform, :output_file, "lib/generated/AshRpc.kt")
  end

  @doc """
  Returns whether to warn on missing RPC configuration.

  Defaults to true.
  """
  def warn_on_missing_rpc_config? do
    Application.get_env(:ash_kotlin_multiplatform, :warn_on_missing_rpc_config, true)
  end

  @doc """
  Returns whether to warn on non-RPC resource references.

  Defaults to true.
  """
  def warn_on_non_rpc_references? do
    Application.get_env(:ash_kotlin_multiplatform, :warn_on_non_rpc_references, true)
  end
end
