# Runtime Invariants

These are the architecture rules the runtime is expected to enforce in code.

## Control spine

All production runtime work should reduce to:

`Intent -> RuntimeOrchestrator.submitIntent -> Planner -> Command -> VerifiedExecutor.execute -> ExecutionOutcome(events) -> CommitCoordinator.commit -> snapshot/query`

## Side effects

- `VerifiedExecutor` is the only execution layer allowed to trigger side effects.
- `ToolDispatcher` is only reachable from `VerifiedExecutor`.
- Public action APIs are adapters that submit typed intent into the orchestrator path.

## State mutation

- `CommitCoordinator.commit(...)` is the only committed state writer.
- Reducers derive committed state from event envelopes.
- Runtime loop code must not call `worldModel.reset(...)` or mutate committed state directly.

## Eventing

- Success paths emit events.
- Failure paths emit events.
- Policy rejections emit events before returning control to the caller.

## Loop boundaries

- `AgentLoop` schedules and forwards work.
- Planning belongs in `DecisionCoordinator`.
- Execution belongs in `RuntimeExecutionDriver -> IntentAPI -> RuntimeOrchestrator`.

## Entrypoint expectations

- Controller host actions
- MCP tools
- Recipe execution
- Loop-driven actions

All of the above should enter the same orchestrator/executor/commit spine instead of maintaining side-effecting compatibility shims.
