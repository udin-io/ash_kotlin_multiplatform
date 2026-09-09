// SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
//
// SPDX-License-Identifier: MIT

// Compile gate for the Kotlin this library emits. `mix
// ash_kotlin_multiplatform.gen_kotlin_fixture` writes one AshRpc.kt per
// subproject; `gradle compileKotlin` then hands them to a real Kotlin compiler.
// Nothing here is published or consumed by the Elixir library — this project
// exists so that "the generated code does not compile" is a red CI check
// instead of a human re-reading emitted strings.
//
// kotlin("jvm") rather than a Kotlin Multiplatform project: the generator emits
// no `expect`/`actual` declarations, so a JVM module resolves every import from
// Maven Central at a fraction of the setup and CI cost. Re-check that with
// `grep -E '(^|\s)(expect|actual)\s'` over the generated file if the generator
// ever starts emitting platform-specific code.

plugins {
    kotlin("jvm") version "2.4.20" apply false
    kotlin("plugin.serialization") version "2.4.20" apply false
}

// kotlinx-datetime is pinned to the last release where `kotlinx.datetime.Instant`
// is a concrete, non-deprecated class. 0.7.0 removed it in favour of
// `kotlin.time.Instant`, and 0.7.1+ re-added it as a deprecated typealias. The
// generator hand-writes `KSerializer<kotlinx.datetime.Instant>` (see
// lib/ash_kotlin_multiplatform/rpc/codegen/kotlin_static.ex), so a newer pin
// would bury real compiler output under deprecation warnings.
val kotlinxDatetimeVersion = "0.6.2"
val kotlinxSerializationVersion = "1.11.0"
val kotlinxCoroutinesVersion = "1.11.0"
val ktorVersion = "3.5.2"

subprojects {
    apply(plugin = "org.jetbrains.kotlin.jvm")
    apply(plugin = "org.jetbrains.kotlin.plugin.serialization")

    repositories {
        mavenCentral()
    }

    // Typed accessors (`implementation(...)`) are not generated inside a
    // `subprojects` block, hence the string notation.
    dependencies {
        "implementation"("org.jetbrains.kotlinx:kotlinx-serialization-json:$kotlinxSerializationVersion")
        "implementation"("org.jetbrains.kotlinx:kotlinx-datetime:$kotlinxDatetimeVersion")
        "implementation"("org.jetbrains.kotlinx:kotlinx-coroutines-core:$kotlinxCoroutinesVersion")
        "implementation"("io.ktor:ktor-client-core:$ktorVersion")
        "implementation"("io.ktor:ktor-client-content-negotiation:$ktorVersion")
        "implementation"("io.ktor:ktor-serialization-kotlinx-json:$ktorVersion")
        "implementation"("io.ktor:ktor-client-websockets:$ktorVersion")
    }

    extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension> {
        jvmToolchain(21)
    }
}
