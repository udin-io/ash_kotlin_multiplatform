# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.PhoenixChannel do
  @moduledoc """
  Generates the Kotlin Phoenix Channel client: connection management with
  reconnection and heartbeats, channel join and leave, the push/receive
  pattern, and an `AshRpcChannel` wrapper for RPC actions.

  ## The wire format is owned here, not by kotlinx.serialization

  The client speaks Phoenix's **v2** protocol, `Phoenix.Socket.V2.JSONSerializer`.
  That is a deliberate choice with two consequences the rest of the generated
  code does not have, and getting either wrong produces frames the server drops
  in silence:

  * The socket appends `vsn=2.0.0` on connect. Phoenix defaults an absent `vsn`
    to `"1.0.0"` (`phoenix/lib/phoenix/socket.ex`, `__connect__/3`), and the v1
    serializer has no binary branch at all, so a binary payload is impossible
    without this. Before issue #49 the client sent no `vsn` and was, unmarked, a
    v1 client.
  * A v2 text frame is the JSON **array** `[join_ref, ref, topic, event, payload]`.
    A `@Serializable` data class would emit an object, which is the v1 shape, so
    `PhoenixMessage` is encoded by hand in the generated `PhoenixSerializer`.

  Binary frames are length-prefixed with one unsigned byte per field, capping
  each of `join_ref`, `ref`, `topic` and `event` at 255 bytes. The layouts are
  **not symmetric** — a client-to-server push carries a ref and a
  server-to-client push does not:

      client -> server  push       [0][joinRefLen][refLen][topicLen][eventLen]  joinRef ref topic event data
      server -> client  push       [0][joinRefLen][topicLen][eventLen]          joinRef topic event data
      server -> client  reply      [1][joinRefLen][refLen][topicLen][statusLen] joinRef ref topic status data
      server -> client  broadcast  [2][topicLen][eventLen]                      topic event data

  Verified against Phoenix 1.8.13:
  `phoenix/lib/phoenix/socket/serializers/v2_json_serializer.ex` (`encode!/1`,
  `decode_binary/1`) and `phoenix/assets/js/phoenix/serializer.js`. The Elixir
  half of that contract is asserted in
  `test/ash_kotlin_multiplatform/rpc/codegen/phoenix_channel_test.exs`, because
  it lives in another package and can change without this repository noticing.
  """

  @doc """
  Generates the complete Phoenix Channel client code for Kotlin.

  Returns one string of top-level Kotlin declarations. Takes no resource and no
  action: the same text is emitted for every application (issue #35).
  """
  def generate do
    """
    #{generate_phoenix_message()}

    #{generate_binary_message()}

    #{generate_channel_payload()}

    #{generate_phoenix_serializer()}

    #{generate_channel_state()}

    #{generate_socket_state()}

    #{generate_push_status()}

    #{generate_push_class()}

    #{generate_phoenix_socket()}

    #{generate_phoenix_channel()}

    #{generate_rpc_channel()}
    """
  end

  defp generate_phoenix_message do
    """
    // A Phoenix protocol message with a JSON payload.
    //
    // Deliberately not @Serializable: a v2 text frame is the JSON array
    // [join_ref, ref, topic, event, payload], and kotlinx.serialization would
    // emit this as an object, which is the v1 shape. PhoenixSerializer builds
    // the array.
    data class PhoenixMessage(
        val joinRef: String?,
        val ref: String?,
        val topic: String,
        val event: String,
        val payload: JsonElement
    ) {
        companion object {
            fun heartbeat(ref: String) = PhoenixMessage(
                joinRef = null,
                ref = ref,
                topic = "phoenix",
                event = "heartbeat",
                payload = JsonObject(emptyMap())
            )

            fun join(topic: String, joinRef: String, ref: String, payload: JsonElement = JsonObject(emptyMap())) =
                PhoenixMessage(joinRef = joinRef, ref = ref, topic = topic, event = "phx_join", payload = payload)

            fun leave(topic: String, joinRef: String, ref: String) =
                PhoenixMessage(joinRef = joinRef, ref = ref, topic = topic, event = "phx_leave", payload = JsonObject(emptyMap()))

            fun push(topic: String, joinRef: String?, ref: String, event: String, payload: JsonElement) =
                PhoenixMessage(joinRef = joinRef, ref = ref, topic = topic, event = event, payload = payload)
        }
    }
    """
  end

  defp generate_binary_message do
    """
    /**
     * A decoded incoming binary frame.
     *
     * Which fields are populated depends on the frame's kind, because Phoenix
     * gives each kind a different header:
     *
     *  - a server push carries a joinRef but no ref;
     *  - a broadcast carries neither;
     *  - a reply carries both, plus a `status`, which sits where a push puts
     *    its event name. `event` is then "phx_reply".
     */
    class PhoenixBinaryMessage(
        val joinRef: String?,
        val ref: String?,
        val topic: String,
        val event: String,
        val status: String?,
        val payload: ByteArray
    )
    """
  end

  defp generate_channel_payload do
    """
    /**
     * What a push carried. Phoenix frames JSON and binary payloads differently,
     * so the difference has to survive as far as the socket, and a reply can
     * come back as either.
     */
    sealed class ChannelPayload {
        data class Json(val element: JsonElement) : ChannelPayload()

        // Not a data class: ByteArray equality is identity, so a generated
        // equals() would claim two frames differ when they hold the same bytes.
        class Binary(val bytes: ByteArray) : ChannelPayload()
    }
    """
  end

  defp generate_phoenix_serializer do
    """
    /**
     * Phoenix's v2 wire protocol.
     *
     * Text frames are the JSON array [join_ref, ref, topic, event, payload].
     * Binary frames are length-prefixed, one unsigned byte per field, and the
     * layout differs by direction and kind. Layouts and the Phoenix source they
     * were read from are in this file's generator moduledoc.
     */
    object PhoenixSerializer {
        // Sent as the `vsn` query parameter. Phoenix defaults an absent vsn to
        // "1.0.0", and the v1 serializer has no binary frame at all.
        const val VSN = "2.0.0"

        const val KIND_PUSH = 0
        const val KIND_REPLY = 1
        const val KIND_BROADCAST = 2

        // Each header length is one unsigned byte.
        const val MAX_FIELD_BYTES = 255

        fun encodeText(message: PhoenixMessage): String =
            JsonArray(
                listOf(
                    jsonString(message.joinRef),
                    jsonString(message.ref),
                    jsonString(message.topic),
                    jsonString(message.event),
                    message.payload
                )
            ).toString()

        fun decodeText(text: String): PhoenixMessage {
            val fields = ashRpcJson.parseToJsonElement(text) as? JsonArray
                ?: throw IllegalArgumentException("Phoenix v2 text frame is not a JSON array")

            require(fields.size >= 5) {
                "Phoenix v2 text frame needs 5 elements, got ${fields.size}"
            }

            return PhoenixMessage(
                joinRef = stringOrNull(fields[0]),
                ref = stringOrNull(fields[1]),
                topic = stringOrNull(fields[2]) ?: "",
                event = stringOrNull(fields[3]) ?: "",
                payload = fields[4]
            )
        }

        /**
         * A client-to-server binary push.
         *
         *     [0][joinRefLen][refLen][topicLen][eventLen] joinRef ref topic event data
         *
         * The ref is what a reply comes back on, so it is required here even
         * though the server's own push frames omit it.
         */
        fun encodeBinaryPush(joinRef: String, ref: String, topic: String, event: String, payload: ByteArray): ByteArray {
            val joinRefBytes = joinRef.encodeToByteArray()
            val refBytes = ref.encodeToByteArray()
            val topicBytes = topic.encodeToByteArray()
            val eventBytes = event.encodeToByteArray()

            assertFieldSize(joinRefBytes.size, "join_ref")
            assertFieldSize(refBytes.size, "ref")
            assertFieldSize(topicBytes.size, "topic")
            assertFieldSize(eventBytes.size, "event")

            val headerSize = 5 + joinRefBytes.size + refBytes.size + topicBytes.size + eventBytes.size
            val frame = ByteArray(headerSize + payload.size)

            frame[0] = KIND_PUSH.toByte()
            frame[1] = joinRefBytes.size.toByte()
            frame[2] = refBytes.size.toByte()
            frame[3] = topicBytes.size.toByte()
            frame[4] = eventBytes.size.toByte()

            var offset = 5
            offset = write(joinRefBytes, frame, offset)
            offset = write(refBytes, frame, offset)
            offset = write(topicBytes, frame, offset)
            offset = write(eventBytes, frame, offset)
            write(payload, frame, offset)

            return frame
        }

        /**
         * A server-to-client binary frame. The kind byte picks the layout;
         * mixing them up misreads every field, so each branch states its own.
         */
        fun decodeBinary(frame: ByteArray): PhoenixBinaryMessage {
            require(frame.isNotEmpty()) { "Phoenix binary frame is empty" }

            return when (val kind = unsigned(frame, 0)) {
                KIND_PUSH -> {
                    // [0][joinRefLen][topicLen][eventLen] joinRef topic event data
                    val joinRefLen = unsigned(frame, 1)
                    val topicLen = unsigned(frame, 2)
                    val eventLen = unsigned(frame, 3)
                    requireLength(frame, 4 + joinRefLen + topicLen + eventLen)

                    var offset = 4
                    val joinRef = frame.decodeToString(offset, offset + joinRefLen)
                    offset += joinRefLen
                    val topic = frame.decodeToString(offset, offset + topicLen)
                    offset += topicLen
                    val event = frame.decodeToString(offset, offset + eventLen)
                    offset += eventLen

                    PhoenixBinaryMessage(joinRef, null, topic, event, null, frame.copyOfRange(offset, frame.size))
                }

                KIND_REPLY -> {
                    // [1][joinRefLen][refLen][topicLen][statusLen] joinRef ref topic status data
                    val joinRefLen = unsigned(frame, 1)
                    val refLen = unsigned(frame, 2)
                    val topicLen = unsigned(frame, 3)
                    val statusLen = unsigned(frame, 4)
                    requireLength(frame, 5 + joinRefLen + refLen + topicLen + statusLen)

                    var offset = 5
                    val joinRef = frame.decodeToString(offset, offset + joinRefLen)
                    offset += joinRefLen
                    val ref = frame.decodeToString(offset, offset + refLen)
                    offset += refLen
                    val topic = frame.decodeToString(offset, offset + topicLen)
                    offset += topicLen
                    val status = frame.decodeToString(offset, offset + statusLen)
                    offset += statusLen

                    PhoenixBinaryMessage(joinRef, ref, topic, "phx_reply", status, frame.copyOfRange(offset, frame.size))
                }

                KIND_BROADCAST -> {
                    // [2][topicLen][eventLen] topic event data
                    val topicLen = unsigned(frame, 1)
                    val eventLen = unsigned(frame, 2)
                    requireLength(frame, 3 + topicLen + eventLen)

                    var offset = 3
                    val topic = frame.decodeToString(offset, offset + topicLen)
                    offset += topicLen
                    val event = frame.decodeToString(offset, offset + eventLen)
                    offset += eventLen

                    PhoenixBinaryMessage(null, null, topic, event, null, frame.copyOfRange(offset, frame.size))
                }

                else -> throw IllegalArgumentException("Unknown Phoenix binary frame kind: $kind")
            }
        }

        private fun jsonString(value: String?): JsonElement =
            if (value == null) JsonNull else JsonPrimitive(value)

        private fun stringOrNull(element: JsonElement): String? =
            if (element is JsonPrimitive && element != JsonNull) element.content else null

        private fun write(source: ByteArray, target: ByteArray, offset: Int): Int {
            source.copyInto(target, offset)
            return offset + source.size
        }

        private fun unsigned(frame: ByteArray, index: Int): Int {
            requireLength(frame, index + 1)
            return frame[index].toInt() and 0xFF
        }

        private fun requireLength(frame: ByteArray, minimum: Int) {
            require(frame.size >= minimum) {
                "Truncated Phoenix binary frame: need at least $minimum bytes, got ${frame.size}"
            }
        }

        private fun assertFieldSize(size: Int, name: String) {
            require(size <= MAX_FIELD_BYTES) {
                "unable to convert $name to binary: must be less than or equal to $MAX_FIELD_BYTES bytes, but is $size bytes"
            }
        }
    }
    """
  end

  defp generate_channel_state do
    """
    // Channel connection states
    enum class ChannelState {
        CLOSED,
        ERRORED,
        JOINED,
        JOINING,
        LEAVING
    }
    """
  end

  defp generate_socket_state do
    """
    // Socket connection states
    enum class SocketState {
        CLOSED,
        CLOSING,
        CONNECTING,
        OPEN
    }
    """
  end

  defp generate_push_status do
    """
    // Push response status
    enum class PushStatus {
        OK,
        ERROR,
        TIMEOUT
    }
    """
  end

  defp generate_push_class do
    """
    // Push represents a message sent to the server awaiting a response.
    //
    // A reply comes back as JSON or as binary independently of what was pushed:
    // a server answering a binary push with a plain map replies in JSON. Hence
    // two lanes, and await()/receive() keep their JSON signatures so every
    // existing caller is untouched.
    class Push(
        val channel: PhoenixChannel,
        val event: String,
        val payload: ChannelPayload,
        private val timeout: Long = 10000L
    ) {
        constructor(channel: PhoenixChannel, event: String, payload: JsonElement, timeout: Long = 10000L) :
            this(channel, event, ChannelPayload.Json(payload), timeout)

        constructor(channel: PhoenixChannel, event: String, payload: ByteArray, timeout: Long = 10000L) :
            this(channel, event, ChannelPayload.Binary(payload), timeout)

        private var ref: String? = null
        private var receivedResponse: ChannelPayload? = null
        private var status: PushStatus? = null
        private val responseCallbacks = mutableMapOf<String, (JsonElement) -> Unit>()
        private val binaryResponseCallbacks = mutableMapOf<String, (ByteArray) -> Unit>()
        private var timeoutCallback: (() -> Unit)? = null
        private val responded = kotlinx.coroutines.CompletableDeferred<Pair<PushStatus, ChannelPayload?>>()

        fun receive(status: String, callback: (JsonElement) -> Unit): Push {
            responseCallbacks[status] = callback
            return this
        }

        fun receiveBinary(status: String, callback: (ByteArray) -> Unit): Push {
            binaryResponseCallbacks[status] = callback
            return this
        }

        fun onTimeout(callback: () -> Unit): Push {
            timeoutCallback = callback
            return this
        }

        internal fun setRef(ref: String) {
            this.ref = ref
        }

        internal fun getRef(): String? = ref

        internal fun matchesRef(ref: String): Boolean = this.ref == ref

        internal fun trigger(status: String, response: JsonElement) {
            complete(status, ChannelPayload.Json(response))
        }

        internal fun triggerBinary(status: String, response: ByteArray) {
            complete(status, ChannelPayload.Binary(response))
        }

        internal fun triggerTimeout() {
            this.status = PushStatus.TIMEOUT
            timeoutCallback?.invoke()
            responded.complete(Pair(PushStatus.TIMEOUT, null))
        }

        /** The reply, when the server sent JSON. Null for a binary reply. */
        suspend fun await(): Pair<PushStatus, JsonElement?> {
            val (pushStatus, response) = awaitPayload()
            return Pair(pushStatus, (response as? ChannelPayload.Json)?.element)
        }

        /** The reply, when the server sent binary. Null for a JSON reply. */
        suspend fun awaitBinary(): Pair<PushStatus, ByteArray?> {
            val (pushStatus, response) = awaitPayload()
            return Pair(pushStatus, (response as? ChannelPayload.Binary)?.bytes)
        }

        /** The reply, whichever form it took. */
        suspend fun awaitPayload(): Pair<PushStatus, ChannelPayload?> {
            return kotlinx.coroutines.withTimeoutOrNull(timeout) {
                responded.await()
            } ?: run {
                triggerTimeout()
                Pair(PushStatus.TIMEOUT, null)
            }
        }

        private fun complete(status: String, response: ChannelPayload) {
            this.status = when (status) {
                "ok" -> PushStatus.OK
                "error" -> PushStatus.ERROR
                else -> PushStatus.ERROR
            }
            this.receivedResponse = response

            when (response) {
                is ChannelPayload.Json -> responseCallbacks[status]?.invoke(response.element)
                is ChannelPayload.Binary -> binaryResponseCallbacks[status]?.invoke(response.bytes)
            }

            responded.complete(Pair(this.status!!, response))
        }
    }
    """
  end

  defp generate_phoenix_socket do
    """
    /**
     * PhoenixSocket manages the WebSocket connection to a Phoenix server.
     *
     * Example usage:
     * ```kotlin
     * val socket = PhoenixSocket(
     *     client = httpClient,
     *     url = "ws://localhost:4000/socket/websocket"
     * )
     * socket.connect()
     *
     * val channel = socket.channel("room:lobby")
     * channel.join()
     * ```
     */
    class PhoenixSocket(
        private val client: HttpClient,
        private val url: String,
        private val params: Map<String, String> = emptyMap(),
        private val heartbeatIntervalMs: Long = 30000L,
        private val reconnectDelayMs: Long = 5000L,
        private val maxReconnectAttempts: Int = 10
    ) {
        private var state: SocketState = SocketState.CLOSED
        private var session: io.ktor.client.plugins.websocket.DefaultClientWebSocketSession? = null
        private var refCounter = 0
        private var reconnectAttempts = 0
        private val channels = mutableMapOf<String, PhoenixChannel>()
        private val pendingPushes = mutableMapOf<String, Push>()
        private var heartbeatJob: kotlinx.coroutines.Job? = null
        private var receiveJob: kotlinx.coroutines.Job? = null
        private var onOpenCallbacks = mutableListOf<() -> Unit>()
        private var onCloseCallbacks = mutableListOf<(Int, String) -> Unit>()
        private var onErrorCallbacks = mutableListOf<(Throwable) -> Unit>()
        private var onMessageCallbacks = mutableListOf<(PhoenixMessage) -> Unit>()
        private var onBinaryMessageCallbacks = mutableListOf<(PhoenixBinaryMessage) -> Unit>()
        private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO + kotlinx.coroutines.SupervisorJob())

        fun generateRef(): String = (++refCounter).toString()

        fun onOpen(callback: () -> Unit): PhoenixSocket {
            onOpenCallbacks.add(callback)
            return this
        }

        fun onClose(callback: (Int, String) -> Unit): PhoenixSocket {
            onCloseCallbacks.add(callback)
            return this
        }

        fun onError(callback: (Throwable) -> Unit): PhoenixSocket {
            onErrorCallbacks.add(callback)
            return this
        }

        fun onMessage(callback: (PhoenixMessage) -> Unit): PhoenixSocket {
            onMessageCallbacks.add(callback)
            return this
        }

        fun onBinaryMessage(callback: (PhoenixBinaryMessage) -> Unit): PhoenixSocket {
            onBinaryMessageCallbacks.add(callback)
            return this
        }

        fun isConnected(): Boolean = state == SocketState.OPEN

        fun connectionState(): SocketState = state

        suspend fun connect() {
            if (state == SocketState.OPEN || state == SocketState.CONNECTING) return

            state = SocketState.CONNECTING
            try {
                val wsUrl = buildUrl()
                session = client.webSocketSession(wsUrl)
                state = SocketState.OPEN
                reconnectAttempts = 0
                onOpenCallbacks.forEach { it() }
                startHeartbeat()
                startReceiving()
            } catch (e: Exception) {
                state = SocketState.CLOSED
                onErrorCallbacks.forEach { it(e) }
                scheduleReconnect()
            }
        }

        suspend fun disconnect(code: Int = 1000, reason: String = "Normal closure") {
            state = SocketState.CLOSING
            heartbeatJob?.cancel()
            receiveJob?.cancel()
            try {
                session?.close(io.ktor.websocket.CloseReason(code.toShort(), reason))
            } catch (_: Exception) {}
            session = null
            state = SocketState.CLOSED
            onCloseCallbacks.forEach { it(code, reason) }
        }

        fun channel(topic: String, params: Map<String, Any?> = emptyMap()): PhoenixChannel {
            return channels.getOrPut(topic) {
                PhoenixChannel(this, topic, params)
            }
        }

        internal suspend fun push(message: PhoenixMessage) {
            session?.send(io.ktor.websocket.Frame.Text(PhoenixSerializer.encodeText(message)))
        }

        internal suspend fun pushBinary(joinRef: String, ref: String, topic: String, event: String, payload: ByteArray) {
            session?.send(
                io.ktor.websocket.Frame.Binary(
                    true,
                    PhoenixSerializer.encodeBinaryPush(joinRef, ref, topic, event, payload)
                )
            )
        }

        internal fun registerPush(push: Push) {
            push.getRef()?.let { pendingPushes[it] = push }
        }

        internal fun removePush(ref: String) {
            pendingPushes.remove(ref)
        }

        // `vsn` selects the server's serializer, and Phoenix defaults an absent
        // one to "1.0.0", whose serializer has no binary frame. It is set here
        // rather than left to the caller, because the frames this client
        // encodes are v2 either way.
        private fun buildUrl(): String {
            val separator = if (url.contains("?")) "&" else "?"
            val allParams = params.filterKeys { it != "vsn" } + ("vsn" to PhoenixSerializer.VSN)
            val queryParams = allParams.entries.joinToString("&") { "${it.key}=${it.value}" }
            return "$url$separator$queryParams"
        }

        private fun startHeartbeat() {
            heartbeatJob?.cancel()
            heartbeatJob = scope.launch {
                while (isActive && state == SocketState.OPEN) {
                    kotlinx.coroutines.delay(heartbeatIntervalMs)
                    if (state == SocketState.OPEN) {
                        try {
                            push(PhoenixMessage.heartbeat(generateRef()))
                        } catch (e: Exception) {
                            onErrorCallbacks.forEach { it(e) }
                        }
                    }
                }
            }
        }

        private fun startReceiving() {
            receiveJob?.cancel()
            receiveJob = scope.launch {
                try {
                    session?.let { ws ->
                        for (frame in ws.incoming) {
                            when (frame) {
                                is io.ktor.websocket.Frame.Text -> {
                                    val text = frame.readText()
                                    try {
                                        handleMessage(PhoenixSerializer.decodeText(text))
                                    } catch (e: Exception) {
                                        onErrorCallbacks.forEach { it(e) }
                                    }
                                }
                                is io.ktor.websocket.Frame.Binary -> {
                                    try {
                                        handleBinaryMessage(PhoenixSerializer.decodeBinary(frame.data))
                                    } catch (e: Exception) {
                                        onErrorCallbacks.forEach { it(e) }
                                    }
                                }
                                is io.ktor.websocket.Frame.Close -> {
                                    val reason = frame.readReason()
                                    disconnect(reason?.code?.toInt() ?: 1000, reason?.message ?: "Connection closed")
                                    scheduleReconnect()
                                }
                                else -> {}
                            }
                        }
                    }
                } catch (e: Exception) {
                    if (state != SocketState.CLOSING && state != SocketState.CLOSED) {
                        onErrorCallbacks.forEach { it(e) }
                        state = SocketState.CLOSED
                        scheduleReconnect()
                    }
                }
            }
        }

        private fun handleMessage(message: PhoenixMessage) {
            onMessageCallbacks.forEach { it(message) }

            // Handle push responses
            message.ref?.let { ref ->
                pendingPushes[ref]?.let { push ->
                    when (message.event) {
                        "phx_reply" -> {
                            val payload = message.payload
                            if (payload is JsonObject) {
                                val status = (payload["status"] as? JsonPrimitive)?.content ?: "error"
                                val response = payload["response"] ?: JsonObject(emptyMap())
                                push.trigger(status, response)
                            }
                            pendingPushes.remove(ref)
                        }
                        "phx_error" -> {
                            push.trigger("error", message.payload)
                            pendingPushes.remove(ref)
                        }
                    }
                }
            }

            // Route to channel
            channels[message.topic]?.handleMessage(message)
        }

        private fun handleBinaryMessage(message: PhoenixBinaryMessage) {
            onBinaryMessageCallbacks.forEach { it(message) }

            // A binary reply resolves the push waiting on its ref. Its status
            // is in the frame header, not in a JSON body, so there is nothing
            // to parse out of the payload.
            message.ref?.let { ref ->
                pendingPushes[ref]?.let { push ->
                    push.triggerBinary(message.status ?: "error", message.payload)
                    pendingPushes.remove(ref)
                    return
                }
            }

            channels[message.topic]?.handleBinaryMessage(message)
        }

        private fun scheduleReconnect() {
            if (reconnectAttempts >= maxReconnectAttempts) return

            scope.launch {
                kotlinx.coroutines.delay(reconnectDelayMs * (reconnectAttempts + 1))
                reconnectAttempts++
                connect()
            }
        }
    }
    """
  end

  defp generate_phoenix_channel do
    """
    /**
     * PhoenixChannel represents a channel subscription on a Phoenix socket.
     *
     * Example usage:
     * ```kotlin
     * val channel = socket.channel("room:lobby")
     *
     * channel.on("new_msg") { payload ->
     *     println("Got message: $payload")
     * }
     *
     * channel.join()
     *     .receive("ok") { println("Joined!") }
     *     .receive("error") { println("Failed to join") }
     * ```
     */
    class PhoenixChannel(
        private val socket: PhoenixSocket,
        val topic: String,
        private val params: Map<String, Any?> = emptyMap()
    ) {
        private var state: ChannelState = ChannelState.CLOSED
        private var joinRef: String? = null
        private var joinPush: Push? = null
        private val bindings = mutableMapOf<String, MutableList<(JsonElement) -> Unit>>()
        private val binaryBindings = mutableMapOf<String, MutableList<(ByteArray) -> Unit>>()
        private val pendingPushes = mutableListOf<Push>()
        fun channelState(): ChannelState = state

        fun isJoined(): Boolean = state == ChannelState.JOINED

        fun isClosed(): Boolean = state == ChannelState.CLOSED

        fun on(event: String, callback: (JsonElement) -> Unit): PhoenixChannel {
            bindings.getOrPut(event) { mutableListOf() }.add(callback)
            return this
        }

        fun off(event: String): PhoenixChannel {
            bindings.remove(event)
            return this
        }

        // Binary events bind separately so `on` keeps its JsonElement callback.
        // A server can send either form under the same event name; bind both if
        // yours does.
        fun onBinary(event: String, callback: (ByteArray) -> Unit): PhoenixChannel {
            binaryBindings.getOrPut(event) { mutableListOf() }.add(callback)
            return this
        }

        fun offBinary(event: String): PhoenixChannel {
            binaryBindings.remove(event)
            return this
        }

        suspend fun join(timeout: Long = 10000L): Push {
            if (state == ChannelState.JOINED || state == ChannelState.JOINING) {
                return joinPush ?: throw IllegalStateException("Channel already joining/joined but no join push")
            }

            state = ChannelState.JOINING
            joinRef = socket.generateRef()

            val payloadJson = ashRpcJson.encodeToJsonElement(params.mapValues { (_, v) ->
                when (v) {
                    is String -> JsonPrimitive(v)
                    is Number -> JsonPrimitive(v)
                    is Boolean -> JsonPrimitive(v)
                    null -> JsonNull
                    else -> JsonPrimitive(v.toString())
                }
            })

            val push = Push(this, "phx_join", payloadJson, timeout)
            val ref = socket.generateRef()
            push.setRef(ref)
            joinPush = push

            push.receive("ok") { state = ChannelState.JOINED }
            push.receive("error") { state = ChannelState.ERRORED }

            val message = PhoenixMessage.join(topic, joinRef!!, ref, payloadJson)
            socket.registerPush(push)
            socket.push(message)

            return push
        }

        suspend fun leave(timeout: Long = 10000L): Push {
            state = ChannelState.LEAVING

            val push = Push(this, "phx_leave", JsonObject(emptyMap()), timeout)
            val ref = socket.generateRef()
            push.setRef(ref)

            push.receive("ok") { state = ChannelState.CLOSED }
            push.receive("error") { state = ChannelState.CLOSED }

            val message = PhoenixMessage.leave(topic, joinRef ?: "", ref)
            socket.registerPush(push)
            socket.push(message)

            return push
        }

        suspend fun push(event: String, payload: JsonElement = JsonObject(emptyMap()), timeout: Long = 10000L): Push {
            if (state != ChannelState.JOINED) {
                throw IllegalStateException("Cannot push on channel that is not joined")
            }

            val push = Push(this, event, payload, timeout)
            val ref = socket.generateRef()
            push.setRef(ref)

            val message = PhoenixMessage.push(topic, joinRef, ref, event, payload)
            socket.registerPush(push)
            socket.push(message)

            return push
        }

        /**
         * Push raw bytes: a JPEG frame, an audio chunk, a file.
         *
         * The server sees `{:binary, data}` as the payload of `handle_in/3`, so
         * nothing is base64-encoded and nothing is re-encoded to measure it. A
         * reply arrives however the server sends it — `await()` for a JSON
         * reply, `awaitBinary()` for a binary one.
         *
         * Requires a joined channel: Phoenix binds a binary push to the join
         * ref, and a channel that has not joined has none.
         */
        suspend fun pushBinary(event: String, payload: ByteArray, timeout: Long = 10000L): Push {
            if (state != ChannelState.JOINED) {
                throw IllegalStateException("Cannot push on channel that is not joined")
            }

            val currentJoinRef = joinRef
                ?: throw IllegalStateException("Cannot push binary on a channel with no join ref")

            val push = Push(this, event, payload, timeout)
            val ref = socket.generateRef()
            push.setRef(ref)

            socket.registerPush(push)
            socket.pushBinary(currentJoinRef, ref, topic, event, payload)

            return push
        }

        internal fun handleMessage(message: PhoenixMessage) {
            bindings[message.event]?.forEach { callback ->
                callback(message.payload)
            }
        }

        internal fun handleBinaryMessage(message: PhoenixBinaryMessage) {
            binaryBindings[message.event]?.forEach { callback ->
                callback(message.payload)
            }
        }

        internal fun getSocket(): PhoenixSocket = socket
    }
    """
  end

  defp generate_rpc_channel do
    """
    /**
     * AshRpcChannel provides a convenient wrapper for Ash RPC operations over Phoenix Channels.
     *
     * Example usage:
     * ```kotlin
     * val socket = PhoenixSocket(client, "ws://localhost:4000/socket/websocket")
     * socket.connect()
     *
     * val rpcChannel = AshRpcChannel(socket, "rpc:lobby")
     * rpcChannel.join()
     *
     * // Call an RPC action
     * val result = rpcChannel.call(
     *     action = "list_todos",
     *     input = mapOf("status" to "active"),
     *     fields = listOf("id", "title", "status")
     * )
     *
     * if (result.isSuccess()) {
     *     val todos = result.dataAs<List<Todo>>()
     *     println("Got todos: $todos")
     * } else {
     *     println("Error: ${result.errors}")
     * }
     * ```
     */
    class AshRpcChannel(
        private val socket: PhoenixSocket,
        topic: String,
        params: Map<String, Any?> = emptyMap()
    ) {
        private val channel = socket.channel(topic, params)
        fun isJoined(): Boolean = channel.isJoined()

        fun channelState(): ChannelState = channel.channelState()

        suspend fun join(timeout: Long = 10000L): Push = channel.join(timeout)

        suspend fun leave(timeout: Long = 10000L): Push = channel.leave(timeout)

        /**
         * Call an Ash RPC action over the channel.
         *
         * @param action The action name (e.g., "list_todos", "create_todo")
         * @param input The input parameters for the action
         * @param fields The fields to return in the response
         * @param timeout Timeout in milliseconds
         * @return RpcResult<JsonElement> with the response data or errors. The channel
         * takes the action name as a string, so there is no type to name here;
         * `dataAs<T>()` is the way through (#22).
         */
        suspend fun call(
            action: String,
            input: Map<String, Any?>? = null,
            fields: List<Any> = emptyList(),
            tenant: String? = null,
            timeout: Long = 10000L
        ): RpcResult<JsonElement> {
            val payload = buildJsonObject {
                put("action", action)
                input?.let { inp ->
                    put("input", ashRpcJson.encodeToJsonElement(inp.mapValues { (_, v) ->
                        when (v) {
                            is String -> JsonPrimitive(v)
                            is Number -> JsonPrimitive(v)
                            is Boolean -> JsonPrimitive(v)
                            null -> JsonNull
                            else -> JsonPrimitive(v.toString())
                        }
                    }))
                }
                putJsonArray("fields") {
                    fields.forEach { field ->
                        when (field) {
                            is String -> add(field)
                            else -> add(ashRpcJson.encodeToJsonElement(field))
                        }
                    }
                }
                tenant?.let { put("tenant", it) }
            }

            val push = channel.push("rpc", payload, timeout)
            val (status, response) = push.await()

            return when (status) {
                PushStatus.OK -> {
                    response?.let { resp ->
                        try {
                            ashRpcJson.decodeFromJsonElement<RpcResult<JsonElement>>(resp)
                        } catch (e: Exception) {
                            RpcResult<JsonElement>(
                                success = false,
                                errors = listOf(AshRpcError(
                                    type = "deserialization_error",
                                    message = "Failed to deserialize response: ${e.message}",
                                    shortMessage = "Deserialization failed"
                                ))
                            )
                        }
                    } ?: RpcResult<JsonElement>(
                        success = false,
                        errors = listOf(AshRpcError(
                            type = "empty_response",
                            message = "Server returned empty response",
                            shortMessage = "Empty response"
                        ))
                    )
                }
                PushStatus.ERROR -> {
                    response?.let { resp ->
                        try {
                            ashRpcJson.decodeFromJsonElement<RpcResult<JsonElement>>(resp)
                        } catch (e: Exception) {
                            RpcResult<JsonElement>(
                                success = false,
                                errors = listOf(AshRpcError(
                                    type = "error",
                                    message = resp.toString(),
                                    shortMessage = "RPC Error"
                                ))
                            )
                        }
                    } ?: RpcResult<JsonElement>(
                        success = false,
                        errors = listOf(AshRpcError(
                            type = "unknown_error",
                            message = "Unknown error occurred",
                            shortMessage = "Unknown error"
                        ))
                    )
                }
                PushStatus.TIMEOUT -> {
                    RpcResult<JsonElement>(
                        success = false,
                        errors = listOf(AshRpcError(
                            type = "timeout",
                            message = "Request timed out after ${timeout}ms",
                            shortMessage = "Timeout"
                        ))
                    )
                }
            }
        }

        /**
         * Subscribe to real-time events on the channel.
         *
         * @param event The event name to subscribe to
         * @param callback The callback to invoke when the event is received
         */
        fun on(event: String, callback: (JsonElement) -> Unit): AshRpcChannel {
            channel.on(event, callback)
            return this
        }

        /**
         * Unsubscribe from an event.
         *
         * @param event The event name to unsubscribe from
         */
        fun off(event: String): AshRpcChannel {
            channel.off(event)
            return this
        }

        /**
         * Push raw bytes on the channel — an image frame, an audio chunk, a
         * file — instead of base64 inside a JSON payload.
         *
         * The server receives `{:binary, data}` as the payload of `handle_in/3`.
         * There is no RPC envelope around it: unlike [call], this sends the
         * bytes and nothing else, so the event name is what tells the server
         * what they are.
         *
         * @param event The event name the server matches in handle_in/3
         * @param payload The bytes to send
         * @param timeout Timeout in milliseconds
         * @return the Push, to await a reply on
         */
        suspend fun pushBinary(event: String, payload: ByteArray, timeout: Long = 10000L): Push =
            channel.pushBinary(event, payload, timeout)

        /**
         * Subscribe to binary events on the channel.
         *
         * Separate from [on], which delivers JSON. A server that sends both
         * forms under one event name needs both bindings.
         */
        fun onBinary(event: String, callback: (ByteArray) -> Unit): AshRpcChannel {
            channel.onBinary(event, callback)
            return this
        }

        /**
         * Unsubscribe from a binary event.
         */
        fun offBinary(event: String): AshRpcChannel {
            channel.offBinary(event)
            return this
        }
    }
    """
  end
end
