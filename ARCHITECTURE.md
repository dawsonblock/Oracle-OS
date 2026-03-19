# Oracle OS Architecture

This document describes the runtime architecture that the code is expected to enforce today.

## Enforced control spine

Production runtime work should flow through one inspectable path:

```text
Intent
  -> RuntimeOrchestrator.submitIntent
  -> Planner
  -> Command
  -> VerifiedExecutor.execute
  -> ExecutionOutcome(events)
  -> CommitCoordinator.commit
  -> RuntimeSnapshot / downstream evaluation
```

## Runtime diagram

```text
controller / MCP / recipes / loop driver
                |
                v
         ActionIntent adapter
                |
                v
              Intent
                |
                v
     RuntimeOrchestrator.submitIntent
                |
      +---------+----------+
      |                    |
      v                    v
   Planner             Policy check
      |                    |
      +---------+----------+
                v
             Command
                |
                v
      VerifiedExecutor.execute
                |
                v
          ToolDispatcher
                |
                v
      ExecutionOutcome(events)
                |
                v
      CommitCoordinator.commit
                |
                v
           World snapshot
```

## Runtime invariants

- `VerifiedExecutor` is the only execution layer allowed to trigger side effects.
- `CommitCoordinator` is the only committed state writer.
- `ToolDispatcher.dispatch(...)` is only called from `VerifiedExecutor`.
- `AgentLoop` must not mutate committed world state directly.
- Success and failure paths both emit events before state is considered complete.

## Current entrypoints

- CLI: `Sources/oracle/main.swift`
- MCP: `Sources/OracleOS/MCP/MCPServer.swift` + `MCPDispatch.swift`
- Controller host: `Sources/OracleControllerHost/ControllerRuntimeBridge.swift`
- Loop bridge: `Sources/OracleOS/Runtime/RuntimeExecutionDriver.swift`
- Recipe engine: `Sources/OracleOS/Learning/Recipes/RecipeEngine.swift`

## Removed legacy paths

The following compatibility paths are no longer part of the intended runtime:

- `RuntimeOrchestrator.performAction(...)`
- `VerifiedActionExecutor`
- Deprecated `RuntimeOrchestrator(context:)` initializers
- `CodeActionGateway`

See `docs/migration_cleanup.md` for the cleanup record and `docs/runtime_invariants.md` for the rule set.

## Major subsystems

### Runtime

- `RuntimeOrchestrator` owns the plan/execute/commit cycle.
- `RuntimeExecutionDriver` translates loop actions into typed intents.
- `AgentLoop` is expected to stay on the scheduling/orchestration side of the boundary.

### Planning

- `MainPlanner` implements the planner protocol.
- Planning must end at `Command`.
- Planning must not execute, commit, or mutate runtime state directly.

### Execution

- `VerifiedExecutor` validates and coordinates execution.
- `ToolDispatcher` routes typed commands to the grounded UI/code/system runners.
- `ExecutionOutcome` is the transport for status, observations, artifacts, and events.

### Eventing and state

- `CommitCoordinator` appends event envelopes and runs reducers.
- Reducers derive committed state from event history.
- `WorldStateModel` exposes read-only snapshots to runtime consumers.

### Observation and intelligence

- Perception, browser integration, and code intelligence remain read/plan support layers.
- They may inform planning and verification, but they should not become alternate execution spines.

## Known gaps

- Full build/test verification for this change set requires a Swift toolchain; the current cloud agent did not have `swift` installed.
- Reducer coverage and replay fidelity still need continued hardening beyond the trust-boundary cleanup.
- Evals and operator traces should continue moving toward real-run artifacts instead of parallel placeholder stories.
