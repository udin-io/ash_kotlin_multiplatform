# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.PhoenixChannel do
  @moduledoc """
  Generates Kotlin Phoenix Channel client code.

  This module generates a complete Phoenix Channel implementation for Kotlin
  that supports:
  - WebSocket connection management with automatic reconnection
  - Phoenix protocol message format (v2)
  - Heartbeat handling
  - Channel join/leave with callbacks
  - Push/receive pattern for messages
  - RPC-specific convenience methods
  """

  @doc """
  Generates the complete Phoenix Channel client code for Kotlin.
  """
  def generate do
    """
    #{generate_phoenix_message()}

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
    // Phoenix Protocol Message
    @Serializable
    data class PhoenixMessage(
        @SerialName("join_ref")
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
    // Push represents a message sent to the server awaiting a response
    class Push(
        val channel: PhoenixChannel,
        val event: String,
        val payload: JsonElement,
        private val timeout: Long = 10000L
    ) {
        private var ref: String? = null
        private var receivedResponse: JsonElement? = null
        private var status: PushStatus? = null
        private val responseCallbacks = mutableMapOf<String, (JsonElement) -> Unit>()
        private var timeoutCallback: (() -> Unit)? = null
        private val sent = kotlinx.coroutines.CompletableDeferred<Unit>()
        private val responded = kotlinx.coroutines.CompletableDeferred<Pair<PushStatus, JsonElement?>>()

        fun receive(status: String, callback: (JsonElement) -> Unit): Push {
            responseCallbacks[status] = callback
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
            this.status = when (status) {
                "ok" -> PushStatus.OK
                "error" -> PushStatus.ERROR
                else -> PushStatus.ERROR
            }
            this.receivedResponse = response
            responseCallbacks[status]?.invoke(response)
            responded.complete(Pair(this.status!!, response))
        }

        internal fun triggerTimeout() {
            this.status = PushStatus.TIMEOUT
            timeoutCallback?.invoke()
            responded.complete(Pair(PushStatus.TIMEOUT, null))
        }

        suspend fun await(): Pair<PushStatus, JsonElement?> {
            return kotlinx.coroutines.withTimeoutOrNull(timeout) {
                responded.await()
            } ?: run {
                triggerTimeout()
                Pair(PushStatus.TIMEOUT, null)
            }
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
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
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
            session?.send(io.ktor.websocket.Frame.Text(json.encodeToString(PhoenixMessage.serializer(), message)))
        }

        internal fun registerPush(push: Push) {
            push.getRef()?.let { pendingPushes[it] = push }
        }

        internal fun removePush(ref: String) {
            pendingPushes.remove(ref)
        }

        private fun buildUrl(): String {
            val separator = if (url.contains("?")) "&" else "?"
            val queryParams = params.entries.joinToString("&") { "${it.key}=${it.value}" }
            return if (queryParams.isNotEmpty()) "$url$separator$queryParams" else url
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
                                        val message = json.decodeFromString(PhoenixMessage.serializer(), text)
                                        handleMessage(message)
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
        private val pendingPushes = mutableListOf<Push>()
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

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

        suspend fun join(timeout: Long = 10000L): Push {
            if (state == ChannelState.JOINED || state == ChannelState.JOINING) {
                return joinPush ?: throw IllegalStateException("Channel already joining/joined but no join push")
            }

            state = ChannelState.JOINING
            joinRef = socket.generateRef()

            val payloadJson = json.encodeToJsonElement(params.mapValues { (_, v) ->
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

        internal fun handleMessage(message: PhoenixMessage) {
            bindings[message.event]?.forEach { callback ->
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
     * val result = rpcChannel.call<List<Todo>>(
     *     action = "list_todos",
     *     input = mapOf("status" to "active"),
     *     fields = listOf("id", "title", "status")
     * )
     *
     * when (result) {
     *     is RpcSuccess -> println("Got todos: ${result.data}")
     *     is RpcError -> println("Error: ${result.errors}")
     * }
     * ```
     */
    class AshRpcChannel(
        private val socket: PhoenixSocket,
        topic: String,
        params: Map<String, Any?> = emptyMap()
    ) {
        @PublishedApi internal val channel = socket.channel(topic, params)
        @PublishedApi internal val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

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
         * @return RpcResult with the response data or errors
         */
        suspend inline fun <reified T> call(
            action: String,
            input: Map<String, Any?>? = null,
            fields: List<Any> = emptyList(),
            tenant: String? = null,
            timeout: Long = 10000L
        ): RpcResult<T> {
            val payload = buildJsonObject {
                put("action", action)
                input?.let { inp ->
                    put("input", json.encodeToJsonElement(inp.mapValues { (_, v) ->
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
                            else -> add(json.encodeToJsonElement(field))
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
                            json.decodeFromJsonElement<RpcSuccess<T>>(resp)
                        } catch (e: Exception) {
                            RpcError(errors = listOf(AshRpcError(
                                type = "deserialization_error",
                                message = "Failed to deserialize response: ${e.message}",
                                shortMessage = "Deserialization failed"
                            )))
                        }
                    } ?: RpcError(errors = listOf(AshRpcError(
                        type = "empty_response",
                        message = "Server returned empty response",
                        shortMessage = "Empty response"
                    )))
                }
                PushStatus.ERROR -> {
                    response?.let { resp ->
                        try {
                            json.decodeFromJsonElement<RpcError<T>>(resp)
                        } catch (e: Exception) {
                            RpcError(errors = listOf(AshRpcError(
                                type = "error",
                                message = resp.toString(),
                                shortMessage = "RPC Error"
                            )))
                        }
                    } ?: RpcError(errors = listOf(AshRpcError(
                        type = "unknown_error",
                        message = "Unknown error occurred",
                        shortMessage = "Unknown error"
                    )))
                }
                PushStatus.TIMEOUT -> {
                    RpcError(errors = listOf(AshRpcError(
                        type = "timeout",
                        message = "Request timed out after ${timeout}ms",
                        shortMessage = "Timeout"
                    )))
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
    }
    """
  end
end
