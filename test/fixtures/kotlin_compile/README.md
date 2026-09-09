<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# Kotlin compile gate

This Gradle project exists to hand the Kotlin that `ash_kotlin_multiplatform`
emits to a real Kotlin compiler. It answers issue #37: this library's whole
product is Kotlin source, and until now nothing had ever compiled it — five
open defects (#20, #23, #24, #30, #33) are all "the generated code does not
compile", and every one was found by a human reading emitted strings. Nothing
here is published, consumed by the Elixir library, or wired into the app. The
CI job that runs it is `kotlin-compile-gate` in `.github/workflows/ci.yml`.

## Running it

```sh
# From the repository root. MIX_ENV=test is what puts the test domain into
# :ash_domains, so it is what gives the generator resources to emit.
MIX_ENV=test mix ash_kotlin_multiplatform.gen_kotlin_fixture

cd test/fixtures/kotlin_compile
gradle compileKotlin
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

The generated `src/` directories are gitignored. A committed copy could drift
from what the generator actually emits, which is the one thing this fixture
exists to detect.
