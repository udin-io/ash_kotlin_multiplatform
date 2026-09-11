<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# ash_kotlin_multiplatform

This is the hub for everything a new reader needs to know about this
repository. It was written on 2026-09-09, on first contact, because the
repository had no source of truth at all and issue #49 asked for one before
any further change. Each page below answers one question; this page says
which page answers which, and what state that page is in.

## What the system is

An Elixir library that reads Ash resources and domains at compile time and
writes a client for them: one `AshRpc.kt` file of Kotlin, and a parallel
Swift generator. The generated client carries the resource data classes, a
per-action input type, an HTTP RPC function per action returning
`RpcResult<T>` typed on what that action sends back, and a Phoenix Channel
client. The library also ships the server half — a Phoenix
controller and an action runner — so the same Ash domain answers the
requests the generated client makes. It is alpha software; the API changes
between versions.

## The pages

| Page | Answers | Status |
| ---- | ------- | ------ |
| [architecture.md](architecture.md) | How a resource becomes Kotlin and Swift, and what runs at request time | Current as of #25 |
| [decisions.md](decisions.md) | The choices that still shape the code, and what each cost | Current as of #25 |
| [risks.md](risks.md) | What could go wrong, what we watch, what we would do | Current as of #25 |
| [roadmap.md](roadmap.md) | What shipped, what is in flight, what is next, what was refused | Current as of #25 |

## Keeping it current

These pages describe the default branch as it is right now. A page that lags
is worse than no page, because readers trust it. So: every PR that changes
behaviour, structure, a risk or a decision updates them in the same PR. Move
the roadmap item, redraw the diagram the change touched, add or retire the
risk it created or removed, record the decision it made. A merge is not
finished until these pages describe `main`.
