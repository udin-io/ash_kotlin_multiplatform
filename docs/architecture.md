<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# Architecture

How an Ash resource becomes a Kotlin or Swift client, and what runs when
that client makes a call. Drawn on 2026-09-09 from the modules that exist in
`lib/`, not from the README, as the source of truth issue #49 asked for.
Read [PROJECT.md](PROJECT.md) first for what the library is. Update the
diagram in the same PR as any change that adds, removes or re-points a
module.

## 1. Context

Two audiences, one shared Ash domain. A developer runs a mix task to write
the client; a mobile app then calls the server the library also provides.

```mermaid
C4Context
    Person(dev, "Elixir developer", "Runs the codegen task, checks the output in")
    Person(mobile, "Mobile developer", "Consumes AshRpc.kt / AshRpc.swift")

    System(akm, "ash_kotlin_multiplatform", "Reads Ash resources; writes a Kotlin and a Swift client; serves the RPC requests that client makes")

    System_Ext(host, "Host Phoenix app", "Owns the Ash domain, the router, the endpoint and any channel modules")
    System_Ext(ash, "Ash + AshIntrospection", "Resource introspection, the shared RPC pipeline, field formatting")
    System_Ext(app, "Android / iOS app", "Ktor or URLSession over HTTP and WebSocket")

    Rel(dev, akm, "mix ash_kotlin_multiplatform.codegen")
    Rel(akm, ash, "Ash.Info.domains/1, Spark DSL introspection")
    Rel(akm, host, "Extensions on domains and resources; a controller to forward to")
    Rel(mobile, app, "Builds against the generated client")
    Rel(app, host, "POST /rpc/run, WebSocket /socket")
    Rel(host, akm, "Phoenix.Controller delegation")
```

## 2. Containers

The library is one OTP application with two halves that never call each
other. The write half runs at development time and produces text. The serve
half runs at request time inside the host's Phoenix app. They meet only in
the wire contract the generated client encodes.

```mermaid
C4Container
    System_Boundary(akm, "ash_kotlin_multiplatform") {
        Container(tasks, "Mix tasks", "Elixir", "codegen, swift_codegen; writes one file each")
        Container(kgen, "Kotlin generator", "Elixir", "AshKotlinMultiplatform.Rpc.Codegen and its type/function generators")
        Container(sgen, "Swift generator", "Elixir", "AshKotlinMultiplatform.Swift.Codegen; a partial parallel of the Kotlin one")
        Container(dsl, "DSL extensions", "Spark", "AshKotlinMultiplatform.Resource on resources, .Rpc on domains, plus four verifiers")
        Container(serve, "RPC server half", "Elixir", "Phoenix.Controller, Rpc.Runner, Rpc.Pipeline, Rpc.Hooks")
    }

    Container_Ext(gate, "Kotlin compile and round-trip gate", "Gradle + Kotlin 2.4.20", "test/fixtures/kotlin_compile; compiles the emitted Kotlin in CI, then decodes real Runner responses with it")
    System_Ext(ash, "Ash + AshIntrospection", "")
    System_Ext(client, "Generated client", "Kotlin / Swift", "AshRpc.kt, AshRpc.swift")

    Rel(tasks, kgen, "generate_kotlin_code/2")
    Rel(tasks, sgen, "generate_swift_code/2")
    Rel(kgen, dsl, "reads rpc_actions, type_name, field_names")
    Rel(sgen, dsl, "reads the same DSL")
    Rel(kgen, client, "writes AshRpc.kt")
    Rel(sgen, client, "writes AshRpc.swift")
    Rel(gate, kgen, "compiles what it emits, one subproject per datetime_library")
    Rel(gate, serve, "decodes real Runner responses with the generated classes")
    Rel(client, serve, "POST /rpc/run, /rpc/validate")
    Rel(serve, ash, "Ash action through the shared pipeline")
```

The gate is drawn because it is the only thing in the repository that checks
the product. Everything else asserts on strings. It has two halves and they
catch different defects: `gradle compileKotlin` catches Kotlin that does not
compile, and `gradle run` catches Kotlin that compiles and then throws or
reads `null` at decode time (#24, #51, #54). A compiler has no opinion about
what a server actually sends, so the second half decodes responses
`Rpc.Runner` produced.

## 3. Component: the Kotlin generator

`Rpc.Codegen.generate_kotlin_code/2` is the only entry point. It collects
config, runs the verifiers, then concatenates section generators in a fixed
order and joins them into one file. Every generator returns a string; none
of them share state.

```mermaid
flowchart TD
    task["Mix.Tasks.AshKotlinMultiplatform.Codegen"] --> cg["Rpc.Codegen.generate_kotlin_code/2"]

    cg --> coll["Rpc.Codegen.RpcConfigCollector<br/>reads Rpc.Info off each domain"]
    cg --> vc["VerifierChecker<br/>VerifyIdentities, VerifyActionTypes,<br/>VerifyFieldNames, VerifyUniqueTypeNames"]

    coll --> tuples["{resource, action, rpc_action}"]

    tuples --> static["KotlinStatic<br/>imports, type aliases, the shared ashRpcJson,<br/>HttpClient factory, AshRpcError, RpcResult&lt;T&gt;"]
    tuples --> schemas["Codegen.ResourceSchemas<br/>data classes, enums,<br/>sealed unions, embedded"]
    tuples --> types["TypeGenerators.*<br/>InputTypes, MetadataTypes (+ AshMetadata&lt;T, M&gt;),<br/>PaginationTypes (AshPage&lt;T&gt;)"]
    tuples --> filters["Codegen.FilterTypes<br/>Codegen.TypedQueries"]
    tuples --> fns["FunctionGenerators.HttpRenderer<br/>+ FunctionCore, ConfigBuilder,<br/>ActionIntrospection, PayloadBuilder"]
    tuples --> chan["Rpc.Codegen.PhoenixChannel<br/>PhoenixSerializer, PhoenixSocket,<br/>PhoenixChannel, AshRpcChannel"]

    schemas --> tm["Codegen.TypeMapper<br/>Codegen.TypeDiscovery"]
    types --> tm
    filters --> tm

    static --> out["AshRpc.kt"]
    schemas --> out
    types --> out
    filters --> out
    fns --> out
    chan --> out
```

`HttpRenderer` and `FunctionCore` are drawn in one box, but the arrow that
matters runs between them: `FunctionCore.determine_return_type/1` names the
`T` in the `RpcResult<T>` the function returns, and `HttpRenderer` prints it
into the signature. Ktor resolves `.body()` from that declared type, so this
one string is what makes a response decode into a resource class rather than
a `JsonElement` (#22).

Two things about `PhoenixChannel` that the box does not show. It is
**static**: it takes no resource and no action, so the same text is emitted
for every application, which is issue #35. And it is the only generated code
that owns a wire format of its own rather than delegating to
kotlinx.serialization — see the decision on the v2 serializer.

## 4. Component: the request path

The generated Kotlin has two ways to reach an Ash action, and they converge.
The channel leg is only half in this repository: the library generates the
client but ships no `Phoenix.Channel` module, so the host writes the
`handle_in` that calls `Rpc.Runner`.

```mermaid
sequenceDiagram
    participant App as Android app
    participant Ctl as Phoenix.Controller
    participant Ch as Host channel module
    participant Run as Rpc.Runner
    participant Pipe as Rpc.Pipeline
    participant Ash as Ash domain

    App->>Ctl: POST /rpc/run {action, input, fields}
    Ctl->>Run: run_action(otp_app, params, actor:, tenant:)
    Run->>Pipe: parse_request, execute, format_output
    Pipe->>Ash: Ash.read / create / update / destroy
    Ash-->>Pipe: records
    Pipe-->>Run: field-selected map
    Run-->>Ctl: %{success: true, data: ...}
    Ctl-->>App: JSON

    Note over App,Ch: The channel leg. The host owns the channel module.
    App->>Ch: push "rpc" (text) or a binary frame
    Ch->>Run: run_action/3
    Run-->>Ch: result map
    Ch-->>App: phx_reply
```

## 5. The Phoenix channel wire format

The generated channel client speaks Phoenix's **v2** serializer,
`Phoenix.Socket.V2.JSONSerializer`, selected by the `vsn=2.0.0` query
parameter the socket appends on connect. The negotiation is in
`deps/phoenix/lib/phoenix/socket.ex:499` and the serializer list in
`deps/phoenix/lib/phoenix/transports/websocket.ex:29`. Absent a `vsn`,
Phoenix falls back to v1, which has no binary branch at all — that is what
the client did before #49, unmarked.

Text frames are a five-element JSON array, not an object:

```
[join_ref, ref, topic, event, payload]
```

Binary frames are length-prefixed, and the layout differs by direction and
kind. Every length is one unsigned byte, so each of those strings is capped
at 255 bytes.

| Direction | Kind | Header bytes | Fields after the header |
| --------- | ---- | ------------ | ----------------------- |
| Client to server | `0` push | `0`, joinRefLen, refLen, topicLen, eventLen | joinRef, ref, topic, event, data |
| Server to client | `0` push | `0`, joinRefLen, topicLen, eventLen | joinRef, topic, event, data (no ref) |
| Server to client | `1` reply | `1`, joinRefLen, refLen, topicLen, statusLen | joinRef, ref, topic, status, data |
| Server to client | `2` broadcast | `2`, topicLen, eventLen | topic, event, data (no refs) |

The outgoing push carries a ref and the incoming push does not, and a reply
puts its status where a push puts its event name. A client that reuses one
layout for both directions misreads every field, and the result is frames
the server drops in silence.

Both directions are emitted by `Rpc.Codegen.PhoenixChannel` as the generated
`PhoenixSerializer` object. The Elixir half of the contract is asserted byte
for byte in
`test/ash_kotlin_multiplatform/rpc/codegen/phoenix_channel_test.exs`,
against the same `Phoenix.Socket.V2.JSONSerializer` that will decode the
frames.

