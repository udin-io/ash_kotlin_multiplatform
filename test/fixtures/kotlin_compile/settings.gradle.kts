// SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
//
// SPDX-License-Identifier: MIT

rootProject.name = "ash-kotlin-compile-gate"

// One subproject per :datetime_library setting. Both emit the same package and
// the same top-level declarations, so Kotlin rejects them as redeclarations if
// they share a compilation unit.
include("kotlinx-datetime", "java-time")
