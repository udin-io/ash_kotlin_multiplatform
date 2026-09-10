// SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
//
// SPDX-License-Identifier: MIT

// Decodes real Rpc.Runner responses with the classes the generator emits to
// read them, and exits non-zero on any throw or wrong value.
//
// The compile gate next door answers "does the emitted Kotlin compile?". Six of
// this repository's filed defects were that (#20, #23, #30, #33, #44, #45) and
// it catches all six. Three were "the emitted Kotlin compiles and then throws"
// (#24, #51, #54) and nothing caught those, because kotlinc has no opinion about
// whether a @SerialName matches the key the server sends or whether a
// SerializersModule reaches the path that needs it. This file runs the code.
//
// One source shared by both :datetime_library subprojects, so every check must
// compile against java.time and kotlinx-datetime alike: assert on
// `toString()`, never on a concrete date class.
//
// The fixture it reads is written by
// `MIX_ENV=test mix ash_kotlin_multiplatform.gen_roundtrip_fixture`. Adding a
// response there without a check here proves nothing; the two are a pair.

import com.ashkotlinmultiplatform.ash.*
import kotlinx.serialization.json.*
import java.io.File
import kotlin.system.exitProcess

private val responses: JsonObject =
    Json.parseToJsonElement(
        File(
            System.getProperty("ashRpcResponses")
                ?: error("set -DashRpcResponses to the responses.json written by mix ash_kotlin_multiplatform.gen_roundtrip_fixture")
        ).readText()
    ).jsonObject

private fun response(name: String): JsonElement =
    responses[name] ?: error("no '$name' in the fixture; regenerate it")

private fun result(name: String): RpcResult =
    ashRpcJson.decodeFromJsonElement<RpcResult>(response(name))

private var failures = 0

private fun check(name: String, body: () -> String) {
    try {
        println("PASS $name -> ${body()}")
    } catch (e: Throwable) {
        failures++
        println("FAIL $name -> ${e::class.simpleName}: ${e.message?.lines()?.firstOrNull()}")
    }
}

private fun expect(what: String, actual: Any?, expected: Any?) {
    if (actual != expected) throw AssertionError("$what: expected <$expected>, got <$actual>")
}

// #51: a populated untyped map threw `Serializer for class 'Any' is not found`
// while absent and null maps decoded fine, so only a populated one measures it.
private fun populatedUntypedMap(): String {
    val todo = result("populated_untyped_map").dataAs<Todo>()!!
    val metadata = todo.metadata ?: throw AssertionError("metadata decoded as null")

    expect("metadata.retries", metadata["retries"]?.jsonPrimitive?.int, 3)
    expect("metadata.source", metadata["source"]?.jsonPrimitive?.content, "import")
    expect("metadata.verified", metadata["verified"]?.jsonPrimitive?.boolean, true)
    expect("metadata.note", metadata["note"], JsonNull)
    expect("settings.notify", todo.settings?.get("notify")?.jsonPrimitive?.boolean, true)

    return "metadata=$metadata settings=${todo.settings}"
}

// A number too large for Long survives the round trip intact. This is what
// `JsonElement` buys over an `Any` serializer: measured 2026-09-10, the same
// value through a hand-written `Any` serializer decodes to a Double and
// re-encodes as 1.2345678901234567E19, which is a different number.
//
// Only the value is preserved, not the formatting: kotlinx normalises a
// trailing zero, so 1.50 comes back as 1.5.
private fun untypedMapKeepsNumberLiterals(): String {
    val big = "12345678901234567890"
    val sent = """{"id":"1","metadata":{"big":$big}}"""
    val todo = ashRpcJson.decodeFromString<Todo>(sent)

    expect("metadata.big", todo.metadata?.get("big")?.jsonPrimitive?.content, big)
    expect("re-encoded", ashRpcJson.encodeToString(todo), sent)

    return "re-encoded unchanged: $sent"
}

// #54: dataAs() is the documented way to get a typed value out of a result, and
// it built a Json of its own that carried no SerializersModule.
private fun dateFieldsViaDataAs(): String {
    val event = result("date_fields").dataAs<Event>()!!

    expect("startsOn", event.startsOn.toString(), "2026-01-01")
    expect("occurredAt", event.occurredAt.toString(), "2026-01-01T09:30:00Z")
    expect("reminderAts", event.reminderAts?.map { it.toString() }, listOf("2025-12-31T09:30:00Z", "2026-01-01T08:00:00Z"))

    return "startsOn=${event.startsOn} occurredAt=${event.occurredAt} reminderAts=${event.reminderAts}"
}

// #54: the Phoenix channel client held two `Json` instances of its own. It now
// decodes through `ashRpcJson`, so decoding through `ashRpcJson` here is that
// path, not a reproduction of it.
private fun dateFieldsThroughTheChannelJson(): String {
    val data = result("date_fields").data!!
    val event = ashRpcJson.decodeFromJsonElement<Event>(data)

    expect("occurredAt", event.occurredAt.toString(), "2026-01-01T09:30:00Z")

    return "occurredAt=${event.occurredAt}"
}

// #54: every request payload encoded through the `Json` companion, which is
// Json.Default and carries no module. Built by decoding rather than by naming a
// date class, so this one source compiles under both :datetime_library settings.
private fun inputEncoding(): String {
    val sent = """{"name":"Launch","starts_on":"2026-01-01","occurred_at":"2026-01-01T09:30:00Z","reminder_ats":["2025-12-31T09:30:00Z"]}"""
    val input = ashRpcJson.decodeFromString<CreateEventInput>(sent)

    expect("re-encoded", ashRpcJson.encodeToString(input), sent)

    return "re-encoded unchanged: $sent"
}

// #24: every error map Runner builds writes the key "shortMessage" literally,
// under every output_field_formatter.
private fun errorDecodes(): String {
    val error = result("error").errors!!.single()

    expect("shortMessage", error.shortMessage, "Action not found")
    expect("type", error.type, "action_not_found")

    return "shortMessage=${error.shortMessage}"
}

// #24: the server sends no class discriminator, so `valid` has to be one.
private fun validationDecodes(): String {
    val valid = ashRpcJson.decodeFromJsonElement<ValidationResult>(response("validation_valid"))
    val invalid = ashRpcJson.decodeFromJsonElement<ValidationResult>(response("validation_invalid"))

    expect("valid", valid is ValidationValid, true)
    expect("invalid", invalid is ValidationInvalid, true)
    // Asserts `shortMessage` and not the offending field: the server sends
    // `"field": "title"` and `AshRpcError` declares no property for it, so a
    // validation error's field is dropped on decode. Out of scope here — it is
    // the #24 shape again, and wants its own issue.
    expect("invalid.errors", (invalid as ValidationInvalid).errors.single().shortMessage, "Validation failed")

    return "valid=${valid::class.simpleName} invalid=${invalid::class.simpleName}"
}

// #24: a field the client did not ask for is absent, not null, so every
// generated field needs a default.
private fun sparseFieldsetDecodes(): String {
    val authors = result("sparse_fieldset").dataAs<List<Author>>()!!

    expect("id", authors.single().id, null)
    expect("name", authors.single().name, "Ursula Le Guin")

    return "id=${authors.single().id} name=${authors.single().name}"
}

// #24: action metadata arrives inside `data`, not beside it, so RpcResult
// declares no top-level metadata property.
private fun actionMetadataLandsInsideData(): String {
    val result = result("action_metadata")
    val data = result.data!!.jsonObject

    expect("top-level keys", response("action_metadata").jsonObject.keys.sorted(), listOf("data", "success"))
    expect("registeredAt", data["metadata"]?.jsonObject?.get("registeredAt")?.jsonPrimitive?.content, "2026-01-01T00:00:00Z")

    return "data keys=${data.keys}"
}

fun main() {
    check("#51 populated untyped map via dataAs()", ::populatedUntypedMap)
    check("#51 untyped map keeps number literals", ::untypedMapKeepsNumberLiterals)
    check("#54 date fields via dataAs()", ::dateFieldsViaDataAs)
    check("#54 date fields through the channel client's Json", ::dateFieldsThroughTheChannelJson)
    check("#54 input encoding through the shared Json", ::inputEncoding)
    check("#24 error response decodes", ::errorDecodes)
    check("#24 validation results decode", ::validationDecodes)
    check("#24 sparse fieldset decodes", ::sparseFieldsetDecodes)
    check("#24 action metadata lands inside data", ::actionMetadataLandsInsideData)

    if (failures > 0) {
        println("$failures round-trip check(s) failed")
        exitProcess(1)
    }
}
