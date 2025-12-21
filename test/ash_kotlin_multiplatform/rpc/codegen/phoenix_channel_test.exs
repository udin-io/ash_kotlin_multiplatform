# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.PhoenixChannelTest do
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Codegen.PhoenixChannel

  describe "generate/0" do
    test "generates PhoenixMessage data class" do
      result = PhoenixChannel.generate()

      assert result =~ "data class PhoenixMessage"
      assert result =~ "@SerialName(\"join_ref\")"
      assert result =~ "val joinRef: String?"
      assert result =~ "val ref: String?"
      assert result =~ "val topic: String"
      assert result =~ "val event: String"
      assert result =~ "val payload: JsonElement"
    end

    test "generates ChannelState enum" do
      result = PhoenixChannel.generate()

      assert result =~ "enum class ChannelState"
      assert result =~ "CLOSED"
      assert result =~ "ERRORED"
      assert result =~ "JOINED"
      assert result =~ "JOINING"
      assert result =~ "LEAVING"
    end

    test "generates SocketState enum" do
      result = PhoenixChannel.generate()

      assert result =~ "enum class SocketState"
      assert result =~ "CONNECTING"
      assert result =~ "OPEN"
    end

    test "generates PushStatus enum" do
      result = PhoenixChannel.generate()

      assert result =~ "enum class PushStatus"
      assert result =~ "OK"
      assert result =~ "ERROR"
      assert result =~ "TIMEOUT"
    end

    test "generates Push class" do
      result = PhoenixChannel.generate()

      assert result =~ "class Push("
      assert result =~ "fun receive(status: String, callback: (JsonElement) -> Unit): Push"
      assert result =~ "fun onTimeout(callback: () -> Unit): Push"
      assert result =~ "suspend fun await(): Pair<PushStatus, JsonElement?>"
    end

    test "generates PhoenixSocket class" do
      result = PhoenixChannel.generate()

      assert result =~ "class PhoenixSocket("
      assert result =~ "private val client: HttpClient"
      assert result =~ "private val url: String"
      assert result =~ "suspend fun connect()"
      assert result =~ "suspend fun disconnect("
      assert result =~ "fun channel(topic: String"
      assert result =~ "fun isConnected(): Boolean"
      assert result =~ "fun onOpen(callback: () -> Unit)"
      assert result =~ "fun onClose(callback: (Int, String) -> Unit)"
      assert result =~ "fun onError(callback: (Throwable) -> Unit)"
    end

    test "generates PhoenixChannel class" do
      result = PhoenixChannel.generate()

      assert result =~ "class PhoenixChannel("
      assert result =~ "private val socket: PhoenixSocket"
      assert result =~ "val topic: String"
      assert result =~ "suspend fun join(timeout: Long = 10000L): Push"
      assert result =~ "suspend fun leave(timeout: Long = 10000L): Push"
      assert result =~ "suspend fun push(event: String"
      assert result =~ "fun on(event: String, callback: (JsonElement) -> Unit)"
      assert result =~ "fun off(event: String)"
    end

    test "generates AshRpcChannel class" do
      result = PhoenixChannel.generate()

      assert result =~ "class AshRpcChannel("
      assert result =~ "suspend fun call("
      assert result =~ "action: String"
      assert result =~ "input: Map<String, Any?>?"
      assert result =~ "fields: List<Any>"
      assert result =~ "tenant: String?"
      assert result =~ "): RpcResult"
    end

    test "includes heartbeat handling" do
      result = PhoenixChannel.generate()

      assert result =~ "heartbeatIntervalMs"
      assert result =~ "startHeartbeat()"
      assert result =~ "PhoenixMessage.heartbeat"
    end

    test "includes reconnection logic" do
      result = PhoenixChannel.generate()

      assert result =~ "reconnectDelayMs"
      assert result =~ "maxReconnectAttempts"
      assert result =~ "scheduleReconnect()"
    end
  end
end
