# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Phoenix.Controller do
  @moduledoc """
  Phoenix controller helpers for AshKotlinMultiplatform RPC endpoints.

  This module provides a standard implementation for RPC controllers that handle
  Kotlin client requests. It can be used directly or customized for specific needs.

  ## Usage

  Add to your router:

      scope "/api" do
        pipe_through [:api, :authenticate]
        post "/rpc/run", RpcController, :run
      end

  Create your controller:

      defmodule MyAppWeb.RpcController do
        use MyAppWeb, :controller
        use AshKotlinMultiplatform.Phoenix.Controller, otp_app: :my_app

        # Optionally override actor extraction
        def get_actor(conn), do: conn.assigns[:current_user]

        # Optionally override tenant extraction
        def get_tenant(conn), do: conn.assigns[:tenant]
      end

  Or use the minimal approach with defaults:

      defmodule MyAppWeb.RpcController do
        use MyAppWeb, :controller
        use AshKotlinMultiplatform.Phoenix.Controller, otp_app: :my_app
      end

  ## Configuration Options

  - `:otp_app` (required) - Your OTP application name
  - `:actor_key` - Assign key for the actor (default: `:current_user`)
  - `:tenant_key` - Assign key for the tenant (default: `:tenant`)
  - `:require_auth` - Whether to require authentication (default: `true`)

  ## Customization

  Override these functions in your controller:

  - `get_actor/1` - Extract actor from conn (default: `conn.assigns[:current_user]`)
  - `get_tenant/1` - Extract tenant from conn (default: `conn.assigns[:tenant]`)
  - `handle_unauthorized/1` - Custom unauthorized response
  """

  @doc """
  Macro for using this controller module.
  """
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    actor_key = Keyword.get(opts, :actor_key, :current_user)
    tenant_key = Keyword.get(opts, :tenant_key, :tenant)
    require_auth = Keyword.get(opts, :require_auth, true)

    quote do
      import Plug.Conn
      import Phoenix.Controller

      @otp_app unquote(otp_app)
      @actor_key unquote(actor_key)
      @tenant_key unquote(tenant_key)
      @require_auth unquote(require_auth)

      @doc """
      Execute an RPC action.

      This is the main entry point for RPC requests from Kotlin clients.
      """
      def run(conn, params) do
        AshKotlinMultiplatform.Phoenix.Controller.handle_run(
          conn,
          params,
          @otp_app,
          &get_actor/1,
          &get_tenant/1,
          &handle_unauthorized/1,
          @require_auth
        )
      end

      @doc """
      Validate an RPC action without executing it.

      Useful for real-time validation in client apps.
      """
      def validate(conn, params) do
        AshKotlinMultiplatform.Phoenix.Controller.handle_validate(
          conn,
          params,
          @otp_app,
          &get_actor/1,
          &get_tenant/1,
          &handle_unauthorized/1,
          @require_auth
        )
      end

      @doc """
      Extract the actor from the connection.

      Override this function to customize actor extraction.
      """
      def get_actor(conn) do
        conn.assigns[@actor_key]
      end

      @doc """
      Extract the tenant from the connection.

      Override this function to customize tenant extraction.
      """
      def get_tenant(conn) do
        conn.assigns[@tenant_key]
      end

      @doc """
      Handle unauthorized requests.

      Override this function to customize the unauthorized response.
      """
      def handle_unauthorized(conn) do
        AshKotlinMultiplatform.Phoenix.Controller.default_unauthorized_response(conn)
      end

      defoverridable get_actor: 1, get_tenant: 1, handle_unauthorized: 1
    end
  end

  @doc false
  def handle_run(conn, params, otp_app, get_actor, get_tenant, handle_unauthorized, require_auth) do
    actor = get_actor.(conn)
    tenant = get_tenant.(conn)

    if require_auth and is_nil(actor) do
      handle_unauthorized.(conn)
    else
      result = AshKotlinMultiplatform.Rpc.Runner.run_action(otp_app, params, actor: actor, tenant: tenant)
      Phoenix.Controller.json(conn, result)
    end
  end

  @doc false
  def handle_validate(conn, params, otp_app, get_actor, get_tenant, handle_unauthorized, require_auth) do
    actor = get_actor.(conn)
    tenant = get_tenant.(conn)

    if require_auth and is_nil(actor) do
      handle_unauthorized.(conn)
    else
      result = AshKotlinMultiplatform.Rpc.Runner.validate_action(otp_app, params, actor: actor, tenant: tenant)
      Phoenix.Controller.json(conn, result)
    end
  end

  @doc false
  def default_unauthorized_response(conn) do
    conn
    |> Plug.Conn.put_status(:unauthorized)
    |> Phoenix.Controller.json(%{
      "success" => false,
      "errors" => [
        %{
          "type" => "unauthorized",
          "message" => "Authentication required. Please provide a valid bearer token.",
          "shortMessage" => "Unauthorized"
        }
      ]
    })
  end
end
