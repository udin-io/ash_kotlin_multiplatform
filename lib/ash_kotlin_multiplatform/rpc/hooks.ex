# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Hooks do
  @moduledoc """
  Lifecycle hooks for the Kotlin RPC pipeline.

  This module provides a behaviour and default implementation for lifecycle hooks
  that can be injected into the RPC pipeline. Hooks allow custom logic to be
  executed at key points in the request/response lifecycle.

  ## Available Hooks

  - `before_request/2` - Called before executing an Ash action
  - `after_request/3` - Called after executing an Ash action (success or failure)
  - `on_error/3` - Called when an error occurs in the pipeline
  - `transform_input/2` - Transform input before passing to Ash
  - `transform_output/3` - Transform output before sending to client

  ## Usage

  Implement the `AshKotlinMultiplatform.Rpc.Hooks` behaviour:

  ```elixir
  defmodule MyApp.RpcHooks do
    @behaviour AshKotlinMultiplatform.Rpc.Hooks

    @impl true
    def before_request(request, context) do
      # Log, validate, transform, etc.
      {:ok, request}
    end

    @impl true
    def after_request(result, request, context) do
      # Post-processing, logging, etc.
      {:ok, result}
    end

    # ... implement other callbacks
  end
  ```

  Configure in your application:

  ```elixir
  config :ash_kotlin_multiplatform, :hooks, MyApp.RpcHooks
  ```
  """

  alias AshIntrospection.Rpc.Request

  @type context :: %{
          optional(:conn) => Plug.Conn.t(),
          optional(:socket) => Phoenix.Socket.t(),
          optional(:actor) => term(),
          optional(:tenant) => term(),
          optional(atom()) => term()
        }

  @type hook_result(t) :: {:ok, t} | {:error, term()}

  @doc """
  Called before executing an Ash action.

  Can be used to:
  - Validate the request
  - Add additional context
  - Log the incoming request
  - Transform the request

  Return `{:ok, request}` to continue, or `{:error, reason}` to abort.
  """
  @callback before_request(Request.t(), context()) :: hook_result(Request.t())

  @doc """
  Called after executing an Ash action.

  Receives the result (success or error), the original request, and context.
  Can be used for logging, metrics, or post-processing.
  """
  @callback after_request(
              {:ok, term()} | {:error, term()},
              Request.t(),
              context()
            ) :: hook_result(term())

  @doc """
  Called when an error occurs in the pipeline.

  Receives the error, the original request (if available), and context.
  Can be used for error transformation, logging, or recovery.
  """
  @callback on_error(term(), Request.t() | nil, context()) :: hook_result(term())

  @doc """
  Transform input before passing to Ash.

  Called after parsing and before execution. Can modify the input map.
  """
  @callback transform_input(map(), Request.t()) :: hook_result(map())

  @doc """
  Transform output before sending to client.

  Called after processing and before formatting. Can modify the output.
  """
  @callback transform_output(term(), Request.t(), context()) :: hook_result(term())

  @doc """
  Optional callback. Define to only require specific callbacks.

  Returns a list of optional callbacks that don't need to be implemented.
  """
  @callback __optional_callbacks__() :: [atom()]

  @optional_callbacks [
    before_request: 2,
    after_request: 3,
    on_error: 3,
    transform_input: 2,
    transform_output: 3,
    __optional_callbacks__: 0
  ]

  @doc """
  Returns the configured hooks module, or the default no-op hooks.
  """
  def hooks_module do
    Application.get_env(:ash_kotlin_multiplatform, :hooks, __MODULE__.Default)
  end

  @doc """
  Invokes the before_request hook if configured.
  """
  def before_request(request, context) do
    module = hooks_module()

    if function_exported?(module, :before_request, 2) do
      module.before_request(request, context)
    else
      {:ok, request}
    end
  end

  @doc """
  Invokes the after_request hook if configured.
  """
  def after_request(result, request, context) do
    module = hooks_module()

    if function_exported?(module, :after_request, 3) do
      module.after_request(result, request, context)
    else
      {:ok, result}
    end
  end

  @doc """
  Invokes the on_error hook if configured.
  """
  def on_error(error, request, context) do
    module = hooks_module()

    if function_exported?(module, :on_error, 3) do
      module.on_error(error, request, context)
    else
      {:error, error}
    end
  end

  @doc """
  Invokes the transform_input hook if configured.
  """
  def transform_input(input, request) do
    module = hooks_module()

    if function_exported?(module, :transform_input, 2) do
      module.transform_input(input, request)
    else
      {:ok, input}
    end
  end

  @doc """
  Invokes the transform_output hook if configured.
  """
  def transform_output(output, request, context) do
    module = hooks_module()

    if function_exported?(module, :transform_output, 3) do
      module.transform_output(output, request, context)
    else
      {:ok, output}
    end
  end

  # ---------------------------------------------------------------------------
  # Default No-Op Implementation
  # ---------------------------------------------------------------------------

  defmodule Default do
    @moduledoc """
    Default no-op hooks implementation.

    All hooks pass through without modification.
    """

    @behaviour AshKotlinMultiplatform.Rpc.Hooks

    @impl true
    def before_request(request, _context), do: {:ok, request}

    @impl true
    def after_request(result, _request, _context), do: {:ok, result}

    @impl true
    def on_error(error, _request, _context), do: {:error, error}

    @impl true
    def transform_input(input, _request), do: {:ok, input}

    @impl true
    def transform_output(output, _request, _context), do: {:ok, output}
  end
end
