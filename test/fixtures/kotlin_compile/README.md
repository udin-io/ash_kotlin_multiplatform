<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# Kotlin compile and round-trip gate

This Gradle project hands the Kotlin that `ash_kotlin_multiplatform` emits to a
real Kotlin compiler, and then runs it against real `Rpc.Runner` responses. It
answers issues #37 and #58: this library's whole product is Kotlin source, and
until #37 nothing had ever compiled it. Nothing here is published, consumed by
the Elixir library, or wired into the app. The CI job that runs it is
`kotlin-compile-gate` in `.github/workflows/ci.yml`.

Two gates, because they catch different things:

| Gate                | Catches                                           | Filed as                     |
| ------------------- | ------------------------------------------------- | ---------------------------- |
| `gradle compileKotlin` | The emitted Kotlin does not compile            | #20, #23, #30, #33, #44, #45 |
| `gradle run`        | It compiles and then throws or reads `null`       | #24, #51, #54                |

`kotlinc` has no opinion about whether a `@SerialName` matches the key the
server sends, or whether a `SerializersModule` reaches the path that needs it.
So the second gate decodes actual responses with the actual generated classes.

## Running it

```sh
# From the repository root. MIX_ENV=test is what puts the test domain into
# :ash_domains, so it is what gives the generator resources to emit.
MIX_ENV=test mix ash_kotlin_multiplatform.gen_kotlin_fixture
MIX_ENV=test mix ash_kotlin_multiplatform.gen_roundtrip_fixture

cd test/fixtures/kotlin_compile
gradle compileKotlin
gradle run
```

You need a JDK 21 and Gradle 9.7 on the path. There is no committed wrapper —
CI installs Gradle through `gradle/actions/setup-gradle`, which keeps a binary
jar out of the repository.

## Shape

Two subprojects, one per `:datetime_library` setting:

| Subproject         | `datetime_library`   | Emits                          |
| ------------------ | -------------------- | ------------------------------ |
| `kotlinx-datetime` | `:kotlinx_datetime`  | `kotlinx.datetime.*` + a hand-written `Instant` serializer |
| `java-time`        | `:java_time`         | `java.time.*`                  |

They are separate subprojects rather than two files in one because both declare
the same package and the same top-level names, so Kotlin rejects them as
redeclarations if they share a compilation unit.

`kotlin("jvm")` rather than a Kotlin Multiplatform project: the generator emits
no `expect`/`actual` declarations, so a JVM module resolves every import from
Maven Central at a fraction of the setup and CI cost. Re-check that with
`grep -E '(^|\s)(expect|actual)\s'` over a generated file if the generator ever
starts emitting platform-specific code.

## The round-trip harness

`roundtrip/Roundtrip.kt` is hand-written and committed. It is compiled into
**both** subprojects from that one source, so every check has to compile under
`java.time` and `kotlinx-datetime` alike — assert on `toString()`, never on a
concrete date class. It imports `com.ashkotlinmultiplatform.ash.*`, the package
the fixture generator emits for `:ash_kotlin_multiplatform`.

`roundtrip/responses.json` beside it is generated and gitignored. Each entry is
a response `AshKotlinMultiplatform.Rpc.Runner` actually produced, encoded
through `Phoenix.json_library/0` — the encoder
`AshKotlinMultiplatform.Phoenix.Controller` uses — so the bytes are the
bytes a Kotlin client would receive.

Adding a response to the mix task without a check in `Roundtrip.kt` proves
nothing. The two are a pair.

The generated `src/` directories are gitignored for the same reason as
`responses.json`. A committed copy could drift from what the generator actually
emits, which is the one thing this fixture exists to detect.
