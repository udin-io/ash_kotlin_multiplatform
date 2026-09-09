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
      assert result =~ "val joinRef: String?"
      assert result =~ "val ref: String?"
      assert result =~ "val topic: String"
      assert result =~ "val event: String"
      assert result =~ "val payload: JsonElement"
    end

    test "PhoenixMessage is not @Serializable" do
      # A v2 text frame is a JSON array. kotlinx.serialization would emit the
      # data class as an object, which is the v1 shape, so the array is built
      # by hand in PhoenixSerializer instead.
      result = PhoenixChannel.generate()

      refute result =~ "@Serializable\ndata class PhoenixMessage"
      refute result =~ "@SerialName(\"join_ref\")"
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

  describe "the generated PhoenixSerializer" do
    test "negotiates v2, which is the only version with a binary frame" do
      result = PhoenixChannel.generate()

      assert result =~ "const val VSN = \"2.0.0\""
      assert result =~ ~s|("vsn" to PhoenixSerializer.VSN)|
    end

    test "encodes a text frame as the five-element array v2 expects" do
      result = PhoenixChannel.generate()

      assert result =~ "fun encodeText(message: PhoenixMessage): String"
      assert result =~ "fun decodeText(text: String): PhoenixMessage"
      assert result =~ "jsonString(message.joinRef)"
      assert result =~ "jsonString(message.ref)"
      assert result =~ "jsonString(message.topic)"
      assert result =~ "jsonString(message.event)"
    end
  end

  # These pin Phoenix's serializer, which lives in the phoenix package and can
  # change without anything in this repository noticing. Each builds or reads
  # the exact byte layout the generated PhoenixSerializer is written against,
  # so a Phoenix change to the format fails here rather than silently producing
  # frames the server drops. Verified against Phoenix 1.8.13,
  # lib/phoenix/socket/serializers/v2_json_serializer.ex.
  describe "the Phoenix v2 wire format the generated client is written against" do
    alias Phoenix.Socket.V2.JSONSerializer

    test "a text frame is a five-element array, not the object v1 used" do
      {:socket_push, :text, iodata} =
        JSONSerializer.encode!(%Phoenix.Socket.Message{
          join_ref: "7",
          ref: "9",
          topic: "rpc:lobby",
          event: "rpc",
          payload: %{"action" => "list_todos"}
        })

      assert Phoenix.json_library().decode!(IO.iodata_to_binary(iodata)) ==
               ["7", "9", "rpc:lobby", "rpc", %{"action" => "list_todos"}]
    end
  end
end
