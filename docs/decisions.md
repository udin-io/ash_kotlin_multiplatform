<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# Decisions

The choices that still shape this code, one dated entry each: what was
decided, why, and what it cost. Reconstructed on 2026-09-09 from the commit
history and the code, as the source of truth issue #49 asked for. This file
replaces an ADR directory; git is already the journal, so a decision that no
longer shapes anything gets deleted rather than marked superseded. Add an
entry in the same PR as the change that makes the decision.

## 2025-12-20 — Mirror ash_typescript's modular codegen shape

Section generators, one module each, each returning a string, concatenated
in a fixed order by `Rpc.Codegen`. Chosen because `ash_typescript` had
already proven the shape and the port could follow it module for module.

Cost: the generators share no state, so anything that spans sections —
knowing that a referenced type was never emitted, or that two sections
picked the same Kotlin identifier — has no place to live. #33 and #44 both
came from that gap. The fix each time is to thread the fact in from
`Rpc.Codegen` rather than look it up in a generator.

## 2025-12-21 — Ship a Swift generator alongside the Kotlin one

`Swift.Codegen` and `Swift.TypeMapper` were added in the same release as the
Phoenix controller.

Cost: it is half a generator. It has two test files against the Kotlin
side's dozen, it is not in the compile gate, and no CI job compiles Swift at
all. Issue #31 is open on whether to finish it or delete it.

## 2026-09-09 — Depend on AshIntrospection for the shared RPC core

`Rpc.Pipeline` is a thin Kotlin-flavoured wrapper over
`AshIntrospection.Rpc.Pipeline`; `Rpc.Runner` and the field formatters go
through the same package.

Why: field selection, error shaping and formatter rules are identical across
the TypeScript, Kotlin and Swift clients, and three copies would drift.

Cost: a bug in the shared core lands here as a bug in this library with no
local fix. Issue #48 is one — the runner reaches for the type-blind
`format_output/2`.

## 2026-09-09 — Raise dependency floors to the newest patched release

`mix.exs` pins `ash ~> 3.33`, `ash_phoenix >= 2.3.25`, `phoenix >= 1.8.9`,
`plug >= 1.19.5`, each annotated with the CVEs it clears.

Why: a library's floor is what every consumer inherits, so a low floor
silently permits a vulnerable transitive version in an app that never
audited it.

Cost: consumers on older Ash cannot upgrade this library without upgrading
Ash first. Accepted while the package is alpha.

## 2026-09-09 — Compile the generated Kotlin in CI, and block on it

`test/fixtures/kotlin_compile` is a Gradle project with one subproject per
`datetime_library` setting; the `kotlin-compile-gate` job runs
`gradle compileKotlin`. It shipped with `continue-on-error: true` because the
generated Kotlin did not compile, and lost it in #52 once the sixteen errors
it found (#44, #45) were fixed.

Why: this library's entire product is Kotlin source and nothing had ever
compiled it. Five "does not compile" defects had all been found by a human
reading emitted strings.

Cost: CI now needs a JDK and a Gradle, and the gate only compiles what the
test domain's resources produce. A generated shape no test resource has is
still unchecked.

## 2026-09-09 — An unpublished relationship is dropped, not generated

`Author` has a public `has_many :secrets` to a resource the Kotlin DSL never
publishes. `ResourceSchemas.generate_data_class/2` now omits the field
rather than emitting `List<Secret>` against a class that exists nowhere.

Why: the server already refuses it. `Rpc.Runner`'s field selector gates on
`Resource.Info.kotlin_multiplatform_resource?/1`, so a nested request into
`Author.secrets` comes back `unknown_field`. A field no round trip can
deliver is worth nothing to a client. Generating the missing type would
contradict the DSL, and a verifier error would turn any public Ash
relationship into a build break.

Cost: the omission is silent. A developer who expects the field has to know
the destination must carry the `kotlin_multiplatform` extension.

## 2026-09-09 — Contextual serializers for every Kotlin `Any`

Untyped maps, keywords, tuples, unions and unmapped Ash types all landed on
a bare `Any` inside `@Serializable` classes, which does not compile.
`@Contextual` defers the lookup to the `SerializersModule`.

Cost: the failure moves from compile time to run time. Issue #51 is exactly
that: the code now compiles and a populated untyped map still fails to
decode.
