# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Phoenix.ControllerTest do
  @moduledoc """
  What `AshKotlinMultiplatform.Phoenix.Controller` sends over HTTP (#28).
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias AshKotlinMultiplatform.Phoenix.Controller

  defmodule ContextController do
    @moduledoc false
    use AshKotlinMultiplatform.Phoenix.Controller,
      otp_app: :ash_kotlin_multiplatform,
      require_auth: false

    def get_context(_conn), do: %{relabel_errors: "Relabelled"}
  end

  describe "get_context/1" do
    test "hands its map to the error handlers from run/2" do
      params = %{"action" => "fault_return_string"}
      conn = with_log(fn -> ContextController.run(Plug.Test.conn(:post, "/", params), params) end)

      assert %{"errors" => [%{"shortMessage" => "Relabelled"}]} =
               conn |> elem(0) |> Map.fetch!(:resp_body) |> Jason.decode!()
    end

    test "hands its map to the error handlers from validate/2" do
      params = %{"action" => "create_fault", "input" => %{"title" => "ab"}}
      conn = ContextController.validate(Plug.Test.conn(:post, "/", params), params)

      assert %{"errors" => [%{"shortMessage" => "Relabelled"}]} = Jason.decode!(conn.resp_body)
    end
  end

  describe "a result the JSON encoder refuses" do
    test "answers result_unavailable with status 200, not a 500" do
      {conn, log} = with_log(fn -> run(%{"action" => "fault_unencodable"}) end)

      assert conn.status == 200
      assert %{"success" => false, "errors" => [error]} = Jason.decode!(conn.resp_body)
      assert error["type"] == "result_unavailable"
      assert log =~ error["errorId"]
    end
  end

  defp run(params) do
    Controller.handle_run(
      Plug.Test.conn(:post, "/rpc/run", params),
      params,
      :ash_kotlin_multiplatform,
      fn _conn -> nil end,
      fn _conn -> nil end,
      fn _conn -> %{} end,
      &Controller.default_unauthorized_response/1,
      false
    )
  end
end
