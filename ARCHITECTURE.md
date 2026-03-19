<!-- markdownlint-disable MD040 MD060 -->

# Oracle OS Architecture

## Enforced Runtime Path

Only this path is allowed to cause side effects:

```
Intent
→ AgentLoop (scheduler)
→ RuntimeOrchestrator.submitIntent
→ Planner → Command
→ PolicyEngine.validate
→ VerifiedExecutor.execute
→ ExecutionOutcome (events)
→ CommitCoordinator.commit
→ Reducers
→ WorldState snapshot
→ Critic (evaluate)
→ LearningCoordinator
```

Everything else is one of:
- **intake** — IntentSource, CLI, controller, MCP surfaces
- **pure planning** — DecisionCoordinator, Planner, strategies
- **pure reduction** — EventReducer implementations
- **read-only observation** — ObservationBuilder, StateAbstraction
- **UI/view layer** — OracleController, web UI
- **test harness** — OracleOSTests, OracleOSEvals

## Runtime Invariants

1. **`VerifiedExecutor.execute(_:state:)` is the only side-effect entry.**
   No other function in the codebase may perform host automation, shell execution, file mutation, or network I/O as a runtime action.

2. **`CommitCoordinator.commit(_:)` is the only state writer.**
   All state mutations flow through event envelopes → reducers → WorldStateModel.

3. **Reducers are pure.**
   `apply(events:to:)` is deterministic. Same events + same state = same result. No I/O, no network, no shell.

4. **AgentLoop is intake-only.**
   `runAsScheduler(intake:)` pulls intents from IntentSource and forwards to IntentAPI. No planning, no execution, no state coordination.

5. **`RuntimeOrchestrator.submitIntent` is the control spine.**
   Linear pipeline: plan → validate → execute → emit events → commit → evaluate.

6. **Every success and failure emits domain events.**
   Planning failure, policy rejection, execution failure, and success all produce events committed to the event store.

## Removed Legacy Paths

| Surface | Status |
|---------|--------|
| `performAction(...)` on RuntimeOrchestrator | **Deleted** — bypassed VerifiedExecutor |
| `VerifiedActionExecutor` shim class | **Deleted** — performed no verification |
| Deprecated RuntimeOrchestrator inits (`context:`, `context:planner:`) | **Deleted** |
| `_legacyContext` / `_legacyContextStorage` | **Deleted** |
| Synthetic ToolDispatcher outputs ("no-host: skipped") | **Replaced** with errors |

## Core Spine

```
surface → RuntimeOrchestrator.submitIntent → PolicyEngine → VerifiedExecutor → CommitCoordinator → Critic
```

Surfaces:
- Controller (OracleController → OracleControllerHost → Actions)
- MCP
- CLI (oracle executable)
- Recipes (RecipeEngine)

## Dominant Subsystems

| Layer | Role |
|-------|------|
| **Execution kernel** | Verified interaction via VerifiedExecutor |
| **Perception** | Reliable, compressed environment state |
| **Planner** | Goal decomposition and action selection |
| **Evaluator (Critic)** | Detect failure and drive recovery |
| **Memory / Graph** | Persistent learning |

## Command Model

All executable work crosses from planning into execution as a typed `Command`:

```
Command protocol
├── UICommand (clickElement, typeText, focusWindow, readElement, scrollElement)
├── CodeCommand (searchRepository, modifyFile, runBuild, runTests, readFile)
└── SystemCommand (launchApp, openURL)
```

Commands carry `CommandMetadata` (intentID, source, traceTags, planningStrategy).
Commands are routed by `CommandRouter` using `command.commandType`.

## Event Sourcing

```
ExecutionOutcome → [EventEnvelope] → CommitCoordinator → EventStore + Reducers → WorldModelSnapshot
```

Core lifecycle events:
- IntentReceived, CommandPlanned, CommandStarted
- CommandSucceeded, CommandFailed, PolicyRejected
- StateCommitted, EvaluationRecorded
- RecoveryTriggered, RecoveryCompleted

## Module Layout

```
Sources/OracleOS/
├── API/                    (IntentAPI, Intent, IntentResponse)
├── Commands/               (Command protocol, UI/Code/System commands, CommandRouter)
├── Events/                 (EventStore, EventEnvelope, CommitCoordinator, EventReducer, RuntimeEvents)
├── Execution/              (VerifiedExecutor, ToolDispatcher, ExecutionOutcome, Critic, Loop)
│   └── Loop/               (AgentLoop, IntentSource)
├── Runtime/                (RuntimeOrchestrator, RuntimeExecutionDriver, Coordinators)
├── Planning/               (Planner, DecisionCoordinator, Strategies)
├── WorldModel/             (WorldState, WorldStateModel, Observation)
├── Intent/                 (Actions, ActionIntent, PolicyEngine, Schema)
├── Learning/               (Recipes, Memory)
├── Recovery/               (RecoveryEngine, Strategies)
├── Code/                   (WorkspaceRunner, Repository, Skills)
├── Graph/                  (GraphStore, Knowledge tiers)
├── Skills/                 (OS skills)
├── Observability/          (PlanTrace, EventReplay)
└── ...
```

## Trust Model

### Knowledge tiers
- `exploration` → `candidate` → `stable`
- `experiment`, `recovery` (special modes)

### Knowledge classes
- `reusable`, `parameter`, `episode`

Only reusable knowledge is eligible for canonical long-term storage.

## Current Enforcement

- All side effects flow through `VerifiedExecutor.execute` — the single execution gate
- `CommitCoordinator.commit` is the only entity that writes committed state
- `RuntimeOrchestrator.submitIntent` follows linear pipeline: plan → validate → execute → commit → evaluate
- Legacy `performAction` bridges and `VerifiedActionExecutor` shim are **deleted**
- ToolDispatcher throws errors instead of returning synthetic success
- AgentLoop has `runAsScheduler` mode for pure intent forwarding
- Eval baselines are sourced from `EvalBaseline.swift` (not placeholder JSON)
- CI runs build and test as the minimum repo gate
