# Runtime Baseline 36

This baseline records the starting point observed on branch `cursor/runtime-architecture-unification-217b` before the runtime-unification edits in this change set.

## Environment

- Date: 2026-03-19
- Workspace: `/workspace`
- Swift toolchain: unavailable on this cloud agent (`swift: command not found`)
- Saved build log: `logs/runtime_baseline_36_build.log`
- Saved test log: `logs/runtime_baseline_36_test.log`

## Package dependencies

- Local package dependency: `Vendor/AXorcist`
- Swift tools version in `Package.swift`: `6.0`

## Static test inventory

- Static test count detected from source: `685`
- Source of count: `@Test(...)` plus `func test...` patterns under `Tests/`

## Baseline build/test status

- `swift build`: blocked by missing toolchain on this agent
- `swift test`: blocked by missing toolchain on this agent
- Result: baseline captured, executable verification deferred to an environment with Swift installed

## Runtime entrypoints present at baseline

- CLI: `Sources/oracle/main.swift`
- MCP server: `Sources/OracleOS/MCP/MCPServer.swift`
- Controller host bridge: `Sources/OracleControllerHost/ControllerRuntimeBridge.swift`
- Controller host server: `Sources/OracleControllerHost/ControllerHostServer.swift`
- Agent loop driver: `Sources/OracleOS/Runtime/RuntimeExecutionDriver.swift`

## Legacy surfaces observed at baseline

- `RuntimeOrchestrator.performAction(...)` compatibility bridge
- Deprecated `RuntimeOrchestrator(context:)` initializers
- `VerifiedActionExecutor` shim in `Sources/OracleOS/Execution/ActionResult.swift`
- Controller and MCP action entrypoints calling `Actions.*` with the legacy runtime bridge
- `ToolDispatcher` synthetic success branches such as `no-host: skipped` and `no-context: skipped`
- Direct `worldModel.reset(...)` call inside `AgentLoop+Run.swift`

## Baseline conclusion

The repo already contained the intended typed spine (`Intent -> Planner -> Command -> VerifiedExecutor -> CommitCoordinator`) but production entrypoints still bypassed it for several UI action flows. The unification work in this branch targets those remaining bypasses first.
