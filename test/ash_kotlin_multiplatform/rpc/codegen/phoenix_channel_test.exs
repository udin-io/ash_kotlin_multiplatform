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

    test "generates PhoenixBinaryMessage for decoded incoming binary frames" do
      result = PhoenixChannel.generate()

      assert result =~ "class PhoenixBinaryMessage("
      assert result =~ "val status: String?"
      assert result =~ "val payload: ByteArray"
    end

    test "generates ChannelPayload so a push knows what it carried" do
      result = PhoenixChannel.generate()

      assert result =~ "sealed class ChannelPayload"
      assert result =~ "data class Json(val element: JsonElement) : ChannelPayload()"
      assert result =~ "class Binary(val bytes: ByteArray) : ChannelPayload()"
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

    test "writes the client push header as kind, join_ref, ref, topic, event" do
      result = PhoenixChannel.generate()

      assert result =~
               "fun encodeBinaryPush(joinRef: String, ref: String, topic: String, event: String, payload: ByteArray): ByteArray"

      assert result =~ "frame[0] = KIND_PUSH.toByte()"
      assert result =~ "frame[1] = joinRefBytes.size.toByte()"
      assert result =~ "frame[2] = refBytes.size.toByte()"
      assert result =~ "frame[3] = topicBytes.size.toByte()"
      assert result =~ "frame[4] = eventBytes.size.toByte()"
    end

    test "refuses a header field over the 255 bytes a length byte can hold" do
      result = PhoenixChannel.generate()

      assert result =~ "const val MAX_FIELD_BYTES = 255"
      assert result =~ "private fun assertFieldSize(size: Int, name: String)"
    end

    test "decodes all three incoming kinds, each with its own header width" do
      result = PhoenixChannel.generate()

      assert result =~ "fun decodeBinary(frame: ByteArray): PhoenixBinaryMessage"
      assert result =~ "const val KIND_PUSH = 0"
      assert result =~ "const val KIND_REPLY = 1"
      assert result =~ "const val KIND_BROADCAST = 2"
    end
  end

  describe "pushing and receiving binary payloads" do
    test "PhoenixChannel pushes a ByteArray without touching the JSON path" do
      result = PhoenixChannel.generate()

      assert result =~
               "suspend fun pushBinary(event: String, payload: ByteArray, timeout: Long = 10000L): Push"

      # The JSON push keeps its signature: it is every existing caller.
      assert result =~
               "suspend fun push(event: String, payload: JsonElement = JsonObject(emptyMap()), timeout: Long = 10000L): Push"
    end

    test "AshRpcChannel exposes the binary push and binary events" do
      result = PhoenixChannel.generate()

      assert result =~
               "suspend fun pushBinary(event: String, payload: ByteArray, timeout: Long = 10000L): Push ="

      assert result =~ "fun onBinary(event: String, callback: (ByteArray) -> Unit): AshRpcChannel"
    end

    test "PhoenixChannel binds binary events separately from JSON events" do
      result = PhoenixChannel.generate()

      assert result =~
               "fun onBinary(event: String, callback: (ByteArray) -> Unit): PhoenixChannel"

      assert result =~ "fun offBinary(event: String): PhoenixChannel"
      # The JSON binding keeps its JsonElement callback.
      assert result =~ "fun on(event: String, callback: (JsonElement) -> Unit): PhoenixChannel"
    end

    test "the socket reads incoming binary frames instead of dropping them" do
      result = PhoenixChannel.generate()

      assert result =~ "is io.ktor.websocket.Frame.Binary ->"
      assert result =~ "PhoenixSerializer.decodeBinary("

      assert result =~
               "fun onBinaryMessage(callback: (PhoenixBinaryMessage) -> Unit): PhoenixSocket"
    end

    test "a Push can await a binary reply as well as a JSON one" do
      result = PhoenixChannel.generate()

      assert result =~ "suspend fun awaitBinary(): Pair<PushStatus, ByteArray?>"
      assert result =~ "fun receiveBinary(status: String, callback: (ByteArray) -> Unit): Push"
      # The JSON reply keeps its signature.
      assert result =~ "suspend fun await(): Pair<PushStatus, JsonElement?>"
      assert result =~ "fun receive(status: String, callback: (JsonElement) -> Unit): Push"
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

    @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>>

    test "a client-to-server push carries join_ref, ref, topic and event lengths" do
      frame = <<0, 1, 1, 8, 5>> <> "7" <> "9" <> "camera:1" <> "frame" <> @jpeg

      assert %Phoenix.Socket.Message{
               join_ref: "7",
               ref: "9",
               topic: "camera:1",
               event: "frame",
               payload: {:binary, @jpeg}
             } = JSONSerializer.decode!(frame, opcode: :binary)
    end

    test "a server-to-client push carries no ref, so its header is one byte shorter" do
      {:socket_push, :binary, frame} =
        JSONSerializer.encode!(%Phoenix.Socket.Message{
          join_ref: "7",
          ref: "9",
          topic: "camera:1",
          event: "frame",
          payload: {:binary, @jpeg}
        })

      assert frame == <<0, 1, 8, 5>> <> "7" <> "camera:1" <> "frame" <> @jpeg
    end

    test "a reply puts the status where a push puts the event name" do
      {:socket_push, :binary, frame} =
        JSONSerializer.encode!(%Phoenix.Socket.Reply{
          join_ref: "7",
          ref: "9",
          topic: "camera:1",
          status: :ok,
          payload: {:binary, @jpeg}
        })

      assert frame == <<1, 1, 1, 8, 2>> <> "7" <> "9" <> "camera:1" <> "ok" <> @jpeg
    end

    test "a broadcast carries neither join_ref nor ref" do
      {:socket_push, :binary, frame} =
        JSONSerializer.fastlane!(%Phoenix.Socket.Broadcast{
          topic: "camera:1",
          event: "frame",
          payload: {:binary, @jpeg}
        })

      assert frame == <<2, 8, 5>> <> "camera:1" <> "frame" <> @jpeg
    end

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

    test "a header field is capped at the 255 bytes its length byte can hold" do
      oversized = String.duplicate("t", 256)

      assert_raise ArgumentError, ~r/must be less than or equal to 255 bytes/, fn ->
        JSONSerializer.encode!(%Phoenix.Socket.Message{
          join_ref: "7",
          ref: "9",
          topic: oversized,
          event: "frame",
          payload: {:binary, @jpeg}
        })
      end
    end
  end
end
