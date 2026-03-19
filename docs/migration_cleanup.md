# Migration Cleanup Record — Oracle-OS-main 36

This document records what was removed during the runtime-unification-36 upgrade
to prevent the old design from creeping back in.

## Removed Surfaces

### `performAction(...)` — RuntimeOrchestrator extension
- **Location**: `Sources/OracleOS/Execution/ActionResult.swift`
- **What it was**: 4 overloads of a synchronous bridge that bypassed VerifiedExecutor entirely. Called `MainActor.assumeIsolated { action() }` directly.
- **Why removed**: Bypassed the entire typed Command → VerifiedExecutor pipeline. No precondition validation, no safety checks, no event emission.
- **Replaced by**: `RuntimeOrchestrator.submitIntent(_:)` via IntentAPI

### `VerifiedActionExecutor` — Legacy shim class
- **Location**: `Sources/OracleOS/Execution/ActionResult.swift` (lines 144-178)
- **What it was**: A class that claimed to verify actions but simply called the action closure directly and returned the result. No actual verification.
- **Why removed**: False trust boundary. Consuming code checked `executedThroughExecutor` flag but the executor performed zero validation.
- **Replaced by**: `VerifiedExecutor` actor via `RuntimeOrchestrator`

### Deprecated `RuntimeOrchestrator` initializers
- **`init(context: RuntimeContext, planner: any Planner)`**
- **`init(context: RuntimeContext)`**
- **Why removed**: Created RuntimeOrchestrator instances that relied on RuntimeContext for legacy execution, bypassing the typed intent pipeline.
- **Replaced by**: `init(eventStore:commitCoordinator:planner:)` and `init(eventStore:commitCoordinator:)`

### `_legacyContext` / `_legacyContextStorage`
- **Location**: `Sources/OracleOS/Runtime/RuntimeOrchestrator.swift`
- **What it was**: A deprecated `RuntimeContext` property used for backward-compatible access to legacy execution infrastructure.
- **Why removed**: No longer needed after performAction removal.

### `VerifiedActionExecutor` field on `RuntimeContext`
- **Location**: `Sources/OracleOS/Runtime/RuntimeContext.swift`
- **What it was**: A stored property holding the deprecated VerifiedActionExecutor.
- **Why removed**: VerifiedActionExecutor class was deleted.

### Synthetic ToolDispatcher outputs
- **Examples**: `"no-host: skipped"`, `"opened \(url)"`, `"scrolled"`
- **What they were**: Placeholder success responses when capabilities were missing.
- **Why removed**: False positives. Made ToolDispatcher report success when no action was performed.
- **Replaced by**: Proper `ToolDispatcherError.capabilityNotAvailable` throws

### `executor: VerifiedActionExecutor?` parameters on Actions
- **Affected functions**: `Actions.click`, `Actions.typeText`, `Actions.pressKey`, `Actions.focusApp`
- **Also affected**: `RecipeEngine.run`, `RecipeEngine.resume`, `RecipeEngine.executeStep`
- **Why removed**: VerifiedActionExecutor was deleted. Actions now call perform methods directly; the proper execution path is through IntentAPI → RuntimeOrchestrator → VerifiedExecutor.

### `runtime: RuntimeOrchestrator?` parameters on Actions
- **Affected functions**: All Actions.* public methods
- **Why removed**: Was used to call `runtime.performAction(...)` which is now deleted.

## What NOT to re-add

Do not re-introduce:
1. Any `performAction` method on RuntimeOrchestrator
2. Any class named `VerifiedActionExecutor`
3. Any RuntimeOrchestrator init that takes `RuntimeContext`
4. Any synthetic success responses in ToolDispatcher
5. Any direct state mutation outside of CommitCoordinator
6. Any side-effect execution outside of VerifiedExecutor
