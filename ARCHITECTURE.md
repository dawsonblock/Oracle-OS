# Oracle OS Architecture

This document describes the current runtime layers and how they satisfy the governance contract in [GOVERNANCE.md](GOVERNANCE.md).

## Core Spine

Oracle OS has one execution spine:

`surface -> OracleRuntime -> Policy -> VerifiedActionExecutor -> Trace -> runtime-managed graph/memory/recovery update`

Surfaces:

- Controller
- MCP
- CLI
- Recipes

## Layer Map

### Runtime

Primary files:

- `Sources/OracleOS/Runtime/OracleRuntime.swift`
- `Sources/OracleOS/Runtime/RuntimeContext.swift`
- `Sources/OracleOS/Runtime/RuntimeExecutionDriver.swift`
- `Sources/OracleOS/Runtime/TaskContext.swift`

Responsibilities:

- route task/surface context
- evaluate policy
- call verified execution
- own post-execution graph/memory/recovery updates
- fail closed on policy ambiguity

### Observation and Planning State

Primary files:

- `Sources/OracleOS/Core/Observation/*`
- `Sources/OracleOS/Core/PlanningState/*`
- `Sources/OracleOS/Core/World/*`

Responsibilities:

- build canonical observations
- fuse AX and browser signals conservatively
- abstract raw state into reusable planning state

### Planning

Primary files:

- `Sources/OracleOS/Agent/Planning/*`

Responsibilities:

- interpret goals
- choose OS, code, or mixed planning path
- prefer graph-backed steps when available
- stay out of execution internals

### Skills

Primary files:

- `Sources/OracleOS/Agent/Skills/OS/*`
- `Sources/OracleOS/Agent/Skills/Code/*`

Responsibilities:

- compile bounded intents
- resolve semantic targets through ranking for OS actions
- resolve structured workspace actions for code tasks

They do not execute directly.

### Verified Execution

Primary files:

- `Sources/OracleOS/Core/Execution/VerifiedActionExecutor.swift`
- `Sources/OracleOS/Core/ExecutionSemantics/*`

Responsibilities:

- pre/post observation
- postcondition verification
- failure classification
- transition semantics emission
- trace event creation

This is the execution truth boundary, not the planner and not the architecture engine.

### Graph

Primary files:

- `Sources/OracleOS/Graph/*`

Responsibilities:

- persist candidate/stable control knowledge
- enforce trust tiers
- promote, demote, and prune through policy

### Task Graph

Primary files:

- `Sources/OracleOS/TaskGraph/*`

Responsibilities:

- live planning substrate that the planner navigates directly
- maintain current task node pointer and candidate edge expansion
- abstract world state into task-relevant states (not raw UI noise)
- accumulate edge evidence (success/failure counts, cost, latency)
- support recovery via alternate graph edges
- enforce bounded growth (max nodes, max edges, node merging)
- export diagnostics in DOT and JSON formats

The task graph is the canonical representation of the current task position.
The planner operates on task graph nodes and edges — not on raw ephemeral
state alone. Every verified action creates or updates a graph edge, and
recovery branches through alternate edges rather than side channels.

### Memory

Primary files:

- `Sources/OracleOS/Learning/Memory/*`
- `Sources/OracleOS/ProjectMemory/*`

Responsibilities:

- lightweight runtime bias
- long-horizon engineering memory
- explicit classification between reusable knowledge and episode residue

### Recovery

Primary files:

- `Sources/OracleOS/Agent/Recovery/*`

Responsibilities:

- bounded repair actions
- recovery tagging
- recovery-specific evidence

### Architecture Governance

Primary files:

- `Sources/OracleOS/Architecture/*`

Responsibilities:

- emit findings, governance violations, and refactor proposals
- detect boundary drift and coverage gaps
- stay advisory-first except where governance tests hard-fail

## Trust Model

### Knowledge tiers

- `exploration`
- `candidate`
- `stable`
- `experiment`
- `recovery`

### Knowledge classes

- `reusable`
- `parameter`
- `episode`

Only reusable knowledge is eligible for canonical long-term storage.

## Current Enforcement

- runtime owns post-execution updates
- graph promotion blocks experiment and recovery evidence from stable promotion
- target-bearing OS skills resolve through ranking
- project-memory episode residue is kept out of canonical `ProjectMemory/`
- architecture review emits governance reports tied to rule IDs
- CI runs build and test as the minimum repo gate

## Known Boundaries

- experiments may gather evidence in isolated worktrees, but their results only become promotable knowledge after replay through the main runtime
- recovery remains a first-class tracked mode, but not yet a promotable nominal control path
- architecture review is advisory-first; its hard-fail behavior is enforced through tests and governance checks rather than autonomous blocking
