# Runtime Baseline 36

## Branch
unify-runtime-36

## Date
2026-03-18

## Entry Points Found

### CLI
- Sources/oracle/main.swift - Main entry point

### Controller
- Sources/OracleController/OracleControllerApp.swift - Controller app entry

### MCP/HTTP
- Sources/OracleControllerHost/OracleControllerHostMain.swift - Host process

## Key Runtime Files

### Core Orchestration
- Sources/OracleOS/Runtime/RuntimeOrchestrator.swift - Main orchestrator (368 lines)
- Sources/OracleOS/Execution/Loop/AgentLoop.swift - Agent loop (98 lines)
- Sources/OracleOS/Runtime/RuntimeExecutionDriver.swift - Execution driver (69 lines)

### Execution
- Sources/OracleOS/Execution/VerifiedExecutor.swift - Verified executor (78 lines)
- Sources/OracleOS/Execution/ExecutionOutcome.swift - Execution outcome types (64 lines)
- Sources/OracleOS/Execution/ActionResult.swift - Action results + deprecated VerifiedActionExecutor (309 lines)
- Sources/OracleOS/Execution/ToolDispatcher.swift - Tool dispatcher

### Coordinators
- Sources/OracleOS/Runtime/Coordinators/DecisionCoordinator.swift - Decision coordination (154 lines)
- Sources/OracleOS/Runtime/Coordinators/ExecutionCoordinator.swift - Execution coordination
- Sources/OracleOS/Runtime/Coordinators/RecoveryCoordinator.swift - Recovery coordination
- Sources/OracleOS/Runtime/Coordinators/LearningCoordinator.swift - Learning coordination
- Sources/OracleOS/Events/CommitCoordinator.swift - Commit coordination (49 lines)

### Planning
- Sources/OracleOS/Planning/MainPlanner.swift - Main planner
- Sources/OracleOS/Planning/Planner.swift - Planner protocol

## Architecture Issues Identified

1. **Legacy Execution Path**: RuntimeOrchestrator has deprecated `performAction` methods that bypass VerifiedExecutor
2. **Split Responsibilities**: AgentLoop has multiple responsibilities (planner, executor, recovery, learning, state coordination)
3. **VerifiedActionExecutor**: Deprecated shim that provides no actual verification
4. **Missing Command Type**: No canonical Command struct
5. **Events Optional**: ExecutionOutcome events can be empty
6. **ToolDispatcher**: Needs to become CommandRouter

## Note
Swift build/test not run - Swift toolchain not available in this environment. Changes applied based on static code analysis.
