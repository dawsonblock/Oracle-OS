# Architecture Rules

This document is the single source of truth for Oracle-OS architectural invariants.
All contributors must follow these rules. No exceptions without explicit amendment here.

---

## Protected Backbone Modules

These modules form the execution and reasoning spine. They may be strengthened
but not bypassed, duplicated, or replaced without updating this document:

| Module | Role |
|--------|------|
| `VerifiedActionExecutor` | Only path for environment-changing actions |
| `CriticLoop` | Post-action evaluation and failure classification |
| `PlanSimulator` | Simulates plans before commitment |
| `ProgramKnowledgeGraph` | Canonical code structure model |
| `WorldStateModel` | Authoritative world representation |
| `ObservationChangeDetector` | Element-level change detection |
| `TaskGraph` | Runtime task tracking and graph navigation |
| `TraceStore` | Persistent execution evidence |

---

## Required Rules

### R1 — No new planner entry points

The runtime calls exactly one planner API (`Planner` through `DecisionCoordinator`).
All other plan generators (reasoning, LLM, graph search) are internal helpers
consumed by `PlanGenerator` or `Planner`, never called directly from the runtime.

### R2 — No new memory stores

Runtime memory is organized into three categories:

| Category | Purpose |
|----------|---------|
| **Trace** | What happened (execution evidence) |
| **Workflow** | Reusable successful patterns |
| **Knowledge Graph** | Structured facts and symbol relations |

Do not create additional long-lived memory stores. Route new data into one of
these three categories.

### R3 — No runtime imports from controller or UI targets

`OracleRuntime` and all files under `Sources/OracleOS/Runtime/` must import
only `Foundation`. They must never import `AppKit`, `SwiftUI`,
`OracleController`, or any controller/UI module. The controller is a surface,
not a dependency.

### R4 — No environment mutation outside the executor

Every environment-changing action (UI interaction, shell command, file write,
browser navigation, git operation) must flow through `VerifiedActionExecutor`.
The executor stamps `ActionResult.executedThroughExecutor = true` and the
runtime rejects any result without that flag.

Forbidden outside the executor and its commit flow:
- Direct writes to `worldState`, `taskGraph`, or runtime memory stores
  that bypass the verified execution pipeline
- Spawning processes, writing files, or mutating UI state without
  executor evidence

### R5 — Planners choose structure, never execute

Planners must not resolve exact UI targets, mutate files, execute commands,
or inline recovery mechanics. Planning produces intent; execution resolves
and acts.

---

## Enforcement

These rules are enforced by governance tests under
`Tests/OracleOSTests/Governance/`. CI must pass all governance tests before
merge.

---

## Freeze Policy

During active refactoring phases:
- No new subsystem directories under `Sources/OracleOS/`
- All new work routes into existing modules
- Architecture expansion requires matching eval coverage
