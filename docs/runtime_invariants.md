# Runtime Invariants — Oracle-OS

These invariants are enforced by architecture and guarded by tests.

## 1. Only `VerifiedExecutor.execute` may perform side effects

No other function in the codebase may:
- Execute shell commands
- Perform host automation (AX actions, input events)
- Mutate files on disk (outside of event store persistence)
- Make network requests as part of runtime execution

All side effects flow through:
```
Command → VerifiedExecutor.execute(_:state:) → ToolDispatcher → Domain Handler
```

## 2. Only `CommitCoordinator.commit` may mutate state

State transitions happen through:
```
[EventEnvelope] → CommitCoordinator.commit → EventStore.append → Reducers → WorldStateModel
```

No code may directly mutate `WorldStateModel` fields outside of reducers invoked by `CommitCoordinator`.

## 3. Only reducers may derive committed state

```swift
protocol EventReducer: Sendable {
    func apply(events: [EventEnvelope], to state: inout WorldStateModel)
}
```

Reducers must be pure:
- Same events + same state = same output (deterministic)
- No file I/O, network, shell execution, or logging side effects
- State can be replayed from events

## 4. AgentLoop is intake-only

In scheduler mode (`runAsScheduler`):
- Pulls intents from `IntentSource`
- Forwards to `IntentAPI.submitIntent`
- Does not plan, execute, coordinate recovery, or mutate state

## 5. `RuntimeOrchestrator.submitIntent` is the control spine

Linear pipeline:
1. **Plan** — invoke planner to produce a Command
2. **Validate** — PolicyEngine checks the command
3. **Execute** — delegate to VerifiedExecutor
4. **Emit events** — build event envelopes
5. **Commit** — event-sourced state mutation
6. **Evaluate** — critic review for recovery signals

## 6. Every path emits domain events

- Planning failure → `CommandFailed` event committed
- Policy rejection → `PolicyRejected` event committed
- Execution failure → `CommandFailed` event committed
- Execution success → `CommandStarted` + `CommandSucceeded` events committed

No silent failures. The event store can explain every outcome.

## 7. Command is the execution contract

Only typed `Command` values cross from planning into execution:
- `UICommand` (clickElement, typeText, focusWindow, readElement, scrollElement)
- `CodeCommand` (searchRepository, modifyFile, runBuild, runTests, readFile)
- `SystemCommand` (launchApp, openURL)

No string-based actions, loose closures, or untyped dispatch.
