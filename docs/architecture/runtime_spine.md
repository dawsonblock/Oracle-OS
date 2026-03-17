# Runtime Spine Architecture

## Execution Flow (Canonical Path)

```
Intent → IntentAPI → RuntimeOrchestrator.decide() → Planner → Command 
→ RuntimeOrchestrator.execute() → VerifiedExecutor → ExecutionOutcome 
→ RuntimeOrchestrator.commit() → CommitCoordinator → Reducers 
→ WorldState → Critic → Learning
```

## Invariants

### Execution Invariant
**Only VerifiedExecutor may perform side effects.**
- Planners, controllers, memory, critics must NOT execute actions

### State Invariant  
**Only reducers may update committed runtime state.**
- No direct worldModel.reset()
- No graphStore.write()
- No memoryStore.update() outside reducer flow

### History Invariant
**Every committed state change must correspond to one or more DomainEvents.**
- No silent mutations
- Full event ancestry required

### Controller Invariant
**UI and host layers can only call the runtime through IntentAPI.**
- No planner direct calls
- No executor direct calls
- No state mutation

### Planning Invariant
**Planning returns commands only. It does not execute, commit, write memory, or mutate state.**

### Memory Invariant
**Memory influences planning and learning only. Memory never becomes an alternate state authority.**
