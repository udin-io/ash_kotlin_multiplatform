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

// An untyped result: what the Phoenix channel client returns, and what the
// pre-#22 checks below were written against.
private fun result(name: String): RpcResult<JsonElement> =
    ashRpcJson.decodeFromJsonElement<RpcResult<JsonElement>>(response(name))

// A typed result, named the way a generated function names it. `T` is reified,
// so `serializer<RpcResult<T>>()` resolves at each call site — which is the
// same resolution Ktor's `body()` performs from a function's return type.
private inline fun <reified T> typed(name: String): RpcResult<T> =
    ashRpcJson.decodeFromJsonElement<RpcResult<T>>(response(name))

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

// #30: `:vector` reached Kotlin as JsonElement, so a caller unpacked the numbers
// by hand. It is `List<Double>` now.
private fun vectorDecodesAsDoubles(): String {
    val sent = """{"id":"1","embedding":[0.25,-1.5,3.0]}"""
    val todo = ashRpcJson.decodeFromString<Todo>(sent)

    expect("embedding", todo.embedding, listOf(0.25, -1.5, 3.0))

    return "embedding=${todo.embedding}"
}

// #71: the other half of #30, and the half that was actually broken. The check
// above proved Kotlin can read a JSON number array; it could not prove the
// server ever sends one, because until #71 a vector reached the encoder as the
// packed binary `%Ash.Vector{}` carries and raised Jason.EncodeError. This
// reads a real response, so it fails if stage 4 stops formatting the value.
private fun vectorFromARealResponse(): String {
    val todo = result("vector_attribute").dataAs<Todo>()!!

    expect("embedding", todo.embedding, listOf(0.25, -1.5, 3.0))

    return "embedding=${todo.embedding}"
}

// #71: a `field_names` override, asserted where it actually has to hold — the
// generated property reading the key the server really wrote. Both sides
// ignored the option before, so they agreed while doing nothing; a check on the
// class declaration alone would have passed throughout.
private fun fieldNamesOverrideDecodes(): String {
    val author = result("field_names_override").dataAs<Author>()!!

    expect("addressLine1", author.addressLine1, "10 Downing Street")
    expect("name", author.name, "Mapped Name")

    return "addressLine1=${author.addressLine1}"
}

// #71: an untyped map's keys are data, so a key stored as `created_by` comes
// back as `created_by`. Stage 4 used to rename every key it walked, at every
// depth, because it could not tell a field name from a map key. The typed
// `settings` field next to it still gets its declared name camelCased, which is
// the half that says this is a rule rather than an omission.
private fun untypedMapKeysAreNotRenamed(): String {
    val todo = result("populated_untyped_map").dataAs<Todo>()!!
    val metadata = todo.metadata ?: throw AssertionError("metadata decoded as null")

    expect("metadata.created_by", metadata["created_by"]?.jsonPrimitive?.content, "ada")
    expect("metadata.createdBy absent", metadata["createdBy"], null)
    expect("settings.notifyByEmail present", todo.settings?.containsKey("notifyByEmail"), true)
    expect("settings.notify_by_email absent", todo.settings?.get("notify_by_email"), null)

    return "metadata keys=${metadata.keys} settings keys=${todo.settings?.keys}"
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

// #22: every generated function used to return the same untyped RpcResult. Each
// check below decodes into the type `FunctionCore.determine_return_type/1` now
// names for that action, from a response the server really sent.

// create -> RpcResult<Author>.
private fun typedCreateDecodes(): String {
    val author = typed<Author>("typed_create").data!!

    expect("name", author.name, "Typed One")
    expect("email", author.email, "typed.one@e.com")

    return "name=${author.name} email=${author.email}"
}

// read -> RpcResult<AshPage<Author>>, and the un-paginated call answers with a
// bare JSON array, so AshPage has to read a list as well as a page object.
private fun typedListDecodesABareArray(): String {
    val page = typed<AshPage<Author>>("typed_list").data!!

    expect("limit", page.limit, null)
    expect("hasMore", page.hasMore, false)
    expect("contains Typed One", page.results.any { it.name == "Typed One" }, true)

    return "results=${page.results.size} names=${page.results.map { it.name }} limit=${page.limit}"
}

// The same function, the same return type, the other shape: `page` in the
// request makes the server send an offset page object.
private fun typedOffsetPageDecodes(): String {
    val page = typed<AshPage<Author>>("typed_offset_page").data!!
    val count = page.count

    expect("limit", page.limit, 2)
    expect("offset", page.offset, 0)
    expect("hasMore", page.hasMore, true)
    expect("results", page.results.size, 2)
    expect("count is the whole table", count != null && count > 2, true)

    return "limit=${page.limit} offset=${page.offset} count=$count hasMore=${page.hasMore}"
}

// Keyset sends cursors instead of an offset, and `after`/`before` come back null
// unless the request carried them. `previousPage`/`nextPage` were declared
// `String = ""` before #22 — non-nullable, against a server that sends null on
// an empty page.
private fun typedKeysetPageDecodes(): String {
    val page = typed<AshPage<Author>>("typed_keyset_page").data!!

    expect("offset", page.offset, null)
    expect("after", page.after, null)
    expect("before", page.before, null)
    expect("results", page.results.size, 2)
    expect("nextPage is a cursor", page.nextPage.isNullOrEmpty(), false)
    expect("previousPage is a cursor", page.previousPage.isNullOrEmpty(), false)

    return "results=${page.results.size} nextPage=${page.nextPage?.take(12)}… previousPage=${page.previousPage?.take(12)}…"
}

// A get action returns the record itself. `data` is already nullable on
// RpcResult, so the type is `Author`, not `Author?`.
private fun typedGetDecodes(): String {
    val author = typed<Author>("typed_get").data!!

    expect("name", author.name, "Typed One")

    return "name=${author.name}"
}

// A miss is an error response, and it has to decode through the same typed
// result the hit does: `data` absent, `errors` populated.
private fun typedGetMissDecodes(): String {
    val result = typed<Author>("typed_get_miss")
    val error = result.errors!!.single()

    expect("success", result.success, false)
    expect("data", result.data, null)
    expect("shortMessage", error.shortMessage, "Not found")

    return "success=${result.success} data=${result.data} error=${error.shortMessage}"
}

// A destroy returns the destroyed record, not a boolean. `determine_return_type`
// said "Boolean" until #22 and no caller ever found out, because nothing
// referenced it.
private fun typedDestroyDecodes(): String {
    val author = typed<Author>("typed_destroy").data!!

    expect("name", author.name, "Doomed")

    return "name=${author.name}"
}

// A mutation that exposes metadata returns the record wrapped beside it.
private fun typedMetadataEnvelopeDecodes(): String {
    val envelope = typed<AshMetadata<Event, RegisterEventMetadata>>("action_metadata").data!!
    val metadata = envelope.metadata!!

    expect("data.name", envelope.data.name, "Launch")
    expect("metadata.registeredAt", metadata.registeredAt.toString(), "2026-01-01T00:00:00Z")
    expect("metadata.confirmationCode", metadata.confirmationCode, "AKM-1")

    return "data.name=${envelope.data.name} registeredAt=${metadata.registeredAt} confirmationCode=${metadata.confirmationCode}"
}

// ...but only while some metadata survives the client's narrowing. With
// `metadataFields: []` the server sends the bare record from the same function,
// so the same type has to read that too.
private fun typedMetadataEnvelopeReadsTheBareRecord(): String {
    val envelope = typed<AshMetadata<Event, RegisterEventMetadata>>("metadata_narrowed_away").data!!

    expect("metadata", envelope.metadata, null)
    expect("data.name", envelope.data.name, "Launch")

    return "data.name=${envelope.data.name} metadata=${envelope.metadata}"
}

// #25: the rpc_action options the shared core already honoured and the DSL
// never declared. Every shape below is new to the wire, because a get? read had
// no way to say which record it wanted and so ran as a list read.

// The lookup class the config declares is what puts the key on the wire, and
// the server accepts exactly one spelling of it. The fixture's `get_by_hit` was
// produced by sending this object, so if @SerialName drifted the key here would
// stop matching what the server answered to.
private fun getByEncodesTheKeyTheServerReads(): String {
    val sent = """{"id":"11111111-1111-1111-1111-111111111111"}"""
    val getBy = ashRpcJson.decodeFromString<FetchAuthorGetBy>(sent)

    expect("re-encoded", ashRpcJson.encodeToString(getBy), sent)

    return "re-encoded unchanged: $sent"
}

// A get_by read returns the one record, not a list. Decoding it as
// RpcResult<Author> is the measurement: before #25 this action answered with
// the whole table, which this type cannot read at all.
private fun getByHitDecodesOneRecord(): String {
    val author = typed<Author>("get_by_hit").data!!

    expect("name", author.name, "Typed One")
    expect("data is an object", response("get_by_hit").jsonObject["data"] is JsonObject, true)

    return "name=${author.name}"
}

// not_found_error? false: a successful response whose data is null — a
// different shape from the not-found error `typed_get_miss` carries.
private fun notFoundErrorFalseDecodesANull(): String {
    val result = typed<Author>("get_by_null")

    expect("success", result.success, true)
    expect("data", result.data, null)
    expect("errors", result.errors, null)

    return "success=${result.success} data=${result.data}"
}

// The getBy checks reach the client as ordinary errors, so the generated error
// class has to read them. `field` names the offending key.
private fun getByValidationErrorsDecode(): String {
    val missing = typed<Author>("get_by_missing_field").errors!!.single()
    val unexpected = typed<Author>("get_by_unexpected_field").errors!!.single()

    expect("missing.shortMessage", missing.shortMessage, "Missing required getBy fields")
    expect("unexpected.type", unexpected.type, "unexpected_get_by_fields")

    return "missing=${missing.type} unexpected=${unexpected.type}"
}

// enable_filter? / enable_sort? false refuse the parameter rather than dropping
// it. The generated config for these actions declares no such property, so only
// a stale client can produce these — and it has to be able to read the answer.
private fun refusedReadParametersDecode(): String {
    val filter = typed<AshPage<Book>>("filter_refused").errors!!.single()
    val sort = typed<AshPage<Book>>("sort_refused").errors!!.single()

    expect("filter.type", filter.type, "filter_not_supported")
    expect("filter.shortMessage", filter.shortMessage, "Filter not supported")
    expect("sort.type", sort.type, "sort_not_supported")

    return "filter=${filter.type} sort=${sort.type}"
}

fun main() {
    check("#51 populated untyped map via dataAs()", ::populatedUntypedMap)
    check("#51 untyped map keeps number literals", ::untypedMapKeepsNumberLiterals)
    check("#30 a vector decodes as a list of doubles", ::vectorDecodesAsDoubles)
    check("#71 a vector from a real response decodes", ::vectorFromARealResponse)
    check("#71 a field_names override decodes", ::fieldNamesOverrideDecodes)
    check("#71 untyped map keys are not renamed", ::untypedMapKeysAreNotRenamed)
    check("#54 date fields via dataAs()", ::dateFieldsViaDataAs)
    check("#54 date fields through the channel client's Json", ::dateFieldsThroughTheChannelJson)
    check("#54 input encoding through the shared Json", ::inputEncoding)
    check("#24 error response decodes", ::errorDecodes)
    check("#24 validation results decode", ::validationDecodes)
    check("#24 sparse fieldset decodes", ::sparseFieldsetDecodes)
    check("#24 action metadata lands inside data", ::actionMetadataLandsInsideData)
    check("#22 create decodes into RpcResult<Author>", ::typedCreateDecodes)
    check("#22 read decodes a bare array into AshPage<Author>", ::typedListDecodesABareArray)
    check("#22 read decodes an offset page into AshPage<Author>", ::typedOffsetPageDecodes)
    check("#22 read decodes a keyset page into AshPage<Author>", ::typedKeysetPageDecodes)
    check("#22 get decodes into RpcResult<Author>", ::typedGetDecodes)
    check("#22 a get miss decodes through the same typed result", ::typedGetMissDecodes)
    check("#22 destroy decodes the destroyed record", ::typedDestroyDecodes)
    check("#22 metadata envelope decodes into AshMetadata<Event, RegisterEventMetadata>", ::typedMetadataEnvelopeDecodes)
    check("#22 the same envelope reads the bare record", ::typedMetadataEnvelopeReadsTheBareRecord)
    check("#25 getBy encodes the key the server reads", ::getByEncodesTheKeyTheServerReads)
    check("#25 a get_by read decodes one record, not a list", ::getByHitDecodesOneRecord)
    check("#25 not_found_error? false decodes a null", ::notFoundErrorFalseDecodesANull)
    check("#25 getBy validation errors decode", ::getByValidationErrorsDecode)
    check("#25 a refused filter or sort decodes", ::refusedReadParametersDecode)

    if (failures > 0) {
        println("$failures round-trip check(s) failed")
        exitProcess(1)
    }
}
