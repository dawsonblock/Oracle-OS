# Oracle OS Architecture

This document describes the current runtime layers and how they satisfy the governance contract in [GOVERNANCE.md](GOVERNANCE.md).

## Core Spine

Oracle OS has one execution spine:

`surface -> OracleRuntime -> Policy -> VerifiedActionExecutor -> Critic -> Trace -> runtime-managed graph/memory/recovery update`

Surfaces:

- Controller
- MCP
- CLI
- Recipes

## Dominant Subsystems

The system reduces to five dominant layers:

| Layer | Role |
|-------|------|
| **Execution kernel** | Verified interaction with the environment |
| **Perception** | Reliable, compressed environment state |
| **Planner** | Goal decomposition and action selection |
| **Evaluator (Critic)** | Detect failure and drive recovery |
| **Memory / Graph** | Persistent learning |

Everything else is supporting infrastructure.

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
- maintain world state model, state diffs, and state updates

### State Abstraction Engine

Primary files:

- `Sources/OracleOS/StateAbstraction/StateAbstractionEngine.swift`

Responsibilities:

- map raw AX / DOM elements to semantic types (`SemanticElement`)
- deduplicate similar elements
- attach intent labels
- produce minimal `CompressedUIState` for the planner

The planner should never read raw AX trees directly. Instead it receives
compressed state objects such as `Button("Send")`, `Input("Search")`, or
`List("Messages")`. This dramatically reduces reasoning token consumption
and improves planner stability.

### Action Schema System

Primary files:

- `Sources/OracleOS/ActionSchema/ActionSchema.swift`

Responsibilities:

- define typed action schemas with explicit preconditions and postconditions
- provide canonical schema library (`ActionSchemaLibrary`)
- verify preconditions against compressed UI state
- enable planners to operate on stable primitives

The planner should never emit raw instructions like `move mouse to 840, 410`.
It should always emit schemas such as `Click(Button("Send"))`. The executor
resolves the actual coordinates.

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

### Critic (Self-Evaluation Loop)

Primary files:

- `Sources/OracleOS/Critic/CriticLoop.swift`

Responsibilities:

- evaluate every executed action by comparing pre- and post-state
- classify outcome as SUCCESS, PARTIAL_SUCCESS, FAILURE, or UNKNOWN
- check expected postconditions from action schemas
- signal the planner when recovery is needed
- drive graph edge promotion/demotion via verdict outcome

The critic loop is what allows the agent to correct itself. Every action
step is followed by a critic pass that provides the planner with recovery
signals when expected state changes do not occur. The critic verdict
directly influences task graph updates: only critic-confirmed successes
promote an edge; failures and unknowns record failed executions, reducing
the edge's success probability and potentially demoting it.

### Planning Graph Engine

Primary files:

- `Sources/OracleOS/PlanningGraph/PlanningGraphEngine.swift`

Responsibilities:

- store allowed state transitions as a finite action graph
- rank candidate edges by score (success_rate − cost − latency)
- constrain the planner to emit only edges that appear in the graph
- prune weak edges that fall below a success threshold
- record traversal outcomes to update edge statistics

The planner should operate over a finite action graph instead of
generating arbitrary step sequences. Each edge connects two abstract
task states via a concrete `ActionSchema`.

### Trace Replay Engine

Primary files:

- `Sources/OracleOS/TraceReplay/TraceReplayEngine.swift`

Responsibilities:

- record execution steps as `ReplayStep` values from critic verdicts
- collect steps into `ReplayTrace` for an entire session
- compare expected traces against replayed traces
- surface divergences for debugging and regression analysis

Deterministic replay makes debugging autonomous behaviour tractable.
Every step records the pre/post state hash, action name, critic outcome,
and latency.

### State Memory Index

Primary files:

- `Sources/OracleOS/StateMemory/StateMemoryIndex.swift`

Responsibilities:

- index compressed UI states by signature (app + elements)
- track action statistics (attempts, successes) per state
- provide the planner with previously successful strategies
- evict oldest entries when capacity is exceeded

The state memory index allows the planner to reuse known-good strategies
when it encounters a familiar compressed state, reducing exploration
overhead.

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

### Perception and Vision

Primary files:

- `Sources/OracleOS/Perception/*`
- `Sources/OracleOS/Vision/*`

Responsibilities:

- fuse AX tree, vision, screen capture, DOM hints into unified observation
- provide screenshot capture (`ScreenCapture`) for visual grounding
- bridge to vision sidecar for OCR, object detection, layout analysis
- bridge to Chrome DevTools Protocol for structured DOM information

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

## Module Layout

```
OracleCore
├── Core                    (execution, policy, trace, observation, world)
├── Runtime                 (agent loop, coordinators)
├── Agent                   (planning, recovery, skills)
├── StateAbstraction        (compressed semantic UI state)
├── ActionSchema            (typed action schemas)
├── Critic                  (self-evaluation loop)
├── PlanningGraph           (deterministic planning graph)
├── TraceReplay             (execution replay and divergence detection)
├── StateMemory             (compressed state caching and reuse)
├── Perception              (AX + DOM + vision fusion)
├── Vision                  (screen capture, vision sidecar, CDP bridge)
├── HostAutomation          (macOS app control)
├── BrowserAutomation       (browser control)
├── CodeExecution            (safe command execution)
├── CodeIntelligence         (repository indexing)
├── Graph                   (long-term knowledge)
├── TaskGraph               (runtime task tracking)
├── Memory                  (session memory)
├── ProjectMemory           (repository knowledge)
├── Experiments             (parallel patch testing)
├── Reasoning               (LLM clients, plan generation)
├── PromptEngine            (prompt construction)
├── Workflows               (reusable action sequences)
├── Recipes                 (user-defined task macros)
├── MCP                     (Model Context Protocol)
├── Diagnostics             (runtime debugging)
├── Tools                   (utility functions)
├── Strategy                (high-level planning strategies)
└── Learning                (success probability updates)
```

Removed or archived modules:

- `MetaReasoning` — removed (added complexity without measurable gains)
- `Simulation` — removed (rarely useful in UI agents)
- `WorldModel` — merged into `Core/World`
- `Screenshot` — merged into `Vision`

## Core Control Loop

The integrated control loop after the architecture upgrades:

```
observe environment
  → compress state (StateAbstractionEngine)
  → query state memory for known strategies (StateMemoryIndex)
  → planner chooses action schema (ActionSchemaLibrary / PlanningGraphEngine)
  → executor performs action (VerifiedActionExecutor)
  → critic evaluates result (CriticLoop)
  → critic verdict drives graph promotion/demotion (TaskGraphStore)
  → update state memory with outcome (StateMemoryIndex)
  → record step for replay (TraceReplayEngine)
  → repeat
```

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
