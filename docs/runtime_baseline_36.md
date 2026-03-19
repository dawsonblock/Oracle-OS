# Runtime Baseline — Oracle-OS-main 36

Captured before architecture unification begins.

## Environment

- **Platform target**: macOS 14+
- **Swift version**: 6.0 (swift-tools-version: 6.0)
- **Package dependencies**: AXorcist (vendored at Vendor/AXorcist)
- **Concurrency settings**: StrictConcurrency, ExistentialAny

## Codebase Metrics

| Metric | Count |
|--------|-------|
| Source files (Sources/) | 469 |
| Test files (Tests/) | 111 |
| Products | 5 (OracleOS lib, OracleControllerShared lib, oracle CLI, OracleControllerHost, OracleController) |
| Test targets | 3 (OracleOSTests, OracleOSEvals, OracleControllerTests) |

## Runtime Entrypoints

| Surface | Entry |
|---------|-------|
| CLI | `Sources/oracle/` → oracle executable |
| Controller app | `Sources/OracleController/` → OracleController executable |
| Host process | `Sources/OracleControllerHost/` → OracleControllerHost executable |
| HTTP / MCP | `Sources/OracleOS/MCP/` — MCP server integration |

## Known Legacy Surfaces (pre-unification)

| Legacy Surface | Location | Status |
|----------------|----------|--------|
| `performAction(...)` | `Sources/OracleOS/Execution/ActionResult.swift` (RuntimeOrchestrator extension, 4 overloads) | Deprecated, bypasses VerifiedExecutor |
| `VerifiedActionExecutor` | `Sources/OracleOS/Execution/ActionResult.swift` (lines 144-178) | Deprecated shim, no real verification |
| Deprecated AgentLoop init | `Sources/OracleOS/Execution/Loop/AgentLoop.swift` — single init but holds coordinators directly | Needs narrowing to IntentAPI-only |
| `RuntimeOrchestrator(context:)` | `Sources/OracleOS/Execution/ActionResult.swift` (lines 82-121) | Deprecated initializers |
| `ToolDispatcher` synthetic outputs | `Sources/OracleOS/Execution/ToolDispatcher.swift` | Returns "no-host: skipped", "opened \(url)", "scrolled" |
| `_legacyContext` | `Sources/OracleOS/Runtime/RuntimeOrchestrator.swift` | Deprecated context access |

### Files calling `performAction(...)`

1. `Sources/OracleOS/Intent/Actions/Actions.swift` — click, typeText, pressKey, focusApp, hotkey, scroll, manageWindow
2. `Sources/OracleOS/Execution/ActionResult.swift` — definition site (RuntimeOrchestrator extension)
3. `Sources/OracleControllerHost/ControllerRuntimeBridge.swift` — `performAction(_ request:)` method (different — maps ActionRequest to Actions calls)
4. `Sources/OracleControllerHost/ControllerHostServer.swift` — calls `bridge.performAction(action)`
5. `Sources/OracleController/ControllerStore.swift` — `performAction(_ request:)` (controller → host IPC)
6. `Sources/OracleController/ControllerStore+Copilot.swift` — calls `performAction(actionRequest)`

### Files referencing `VerifiedActionExecutor`

1. `Sources/OracleOS/Execution/ActionResult.swift` — definition
2. `Sources/OracleOS/Intent/Actions/Actions.swift` — parameter + usage in click, typeText, pressKey, focusApp
3. `Sources/OracleOS/Learning/Recipes/RecipeEngine.swift` — parameter + usage in run, resume, executeStep
4. `Sources/OracleOS/Execution/Critic/CriticLoop.swift` — comment reference
5. `Sources/OracleOS/Intent/Schema/ActionSchema.swift` — comment reference
6. `Sources/OracleOS/Search/SearchController.swift` — comment reference
7. `Sources/OracleOS/Runtime/RuntimeContext.swift` — comment or reference
8. `Sources/OracleOS/Runtime/Coordinators/DecisionCoordinator.swift` — comment reference
9. `Tests/OracleOSTests/Governance/CoordinatorBoundaryTests.swift` — governance test
10. `Tests/OracleOSTests/Core/ExecutionKernelBoundaryTests.swift` — boundary test

## Architecture State

The runtime has the correct target architecture documented but not fully enforced:

- **Target path**: Intent → AgentLoop → RuntimeOrchestrator.submitIntent → DecisionCoordinator → Command → VerifiedExecutor.execute → ExecutionOutcome → CommitCoordinator.commit → Reducers → WorldState → Critic → LearningCoordinator
- **Actual state**: Legacy `performAction` bypasses still exist, `VerifiedActionExecutor` shim performs no verification, AgentLoop holds coordinators directly

## Build / Test Status

Build and test verification requires macOS 14+ with Swift 6.0.
Not runnable on current CI Linux environment.
