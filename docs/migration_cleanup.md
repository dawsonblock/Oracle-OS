# Runtime Migration Cleanup

This file records the legacy runtime pieces removed or narrowed by the runtime-unification pass.

## Removed

- `VerifiedActionExecutor`
- `RuntimeOrchestrator.performAction(...)`
- Deprecated `RuntimeOrchestrator(context:)` initializers
- `CodeActionGateway`

## Narrowed

- `ControllerRuntimeBridge` now constructs the primary `RuntimeOrchestrator` with explicit `EventStore`, `CommitCoordinator`, and `ToolDispatcher`.
- `MCPDispatch` now uses the same explicit orchestrator construction path.
- `RuntimeExecutionDriver` translates `ActionIntent` into typed `Intent` metadata and submits through `IntentAPI`.
- `AgentLoop+Run` no longer resets committed world state directly.
- `ToolDispatcher` now grounds UI routing in real action performers instead of synthetic `"no-host: skipped"`/`"no-context: skipped"` success strings.

## Expected follow-on enforcement

- Keep legacy symbols absent with source-scanning integrity tests.
- Keep controller/MCP entrypoints on the typed intent path.
- Keep reducers as the only committed state derivation mechanism.
