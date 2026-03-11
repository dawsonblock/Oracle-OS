# Oracle OS Architecture Status

The descriptive architecture map is in [ARCHITECTURE.md](ARCHITECTURE.md). The normative architectural contract is in [GOVERNANCE.md](GOVERNANCE.md).

## Stable

- `OracleOS` Swift package and `oracle` executable naming
- 22-tool MCP surface
- AX-first perception and core action tools
- Recipe replay and CRUD for JSON recipes
- `ghost_ground` vision grounding
- One runtime-managed execution truth path for policy, verified execution, trace, and outcome handling
- Graph trust tiers and promotion guards for experiment/recovery evidence
- Canonical project memory plus episode-residue separation

## Partial

- Canonical `Observation` snapshots now fuse AX with conservative Chrome CDP candidates
- Verified execution is active for `ghost_click`, `ghost_type`, `ghost_press`, and `ghost_focus`
- JSONL tracing exists for verified actions
- `ghost_parse_screen` is sidecar-backed, but the runtime still treats it as experimental
- Architecture review emits governance reports, but remains advisory-first
- Eval coverage is present but still fixture-heavy

## Scaffold Only

- Workflow synthesis and reusable workflow promotion
- Belief-state reasoning
- Neural policy layers
- Distributed execution

## Not Started

- Distributed multi-agent execution
- Neural transition policies
- OpenFst planning
- Full long-horizon autonomous project execution

## Known Failure Modes

- AX traversal can still be slow or sparse in deep browser and Electron trees
- Chrome CDP enrichment currently assumes Chrome remote debugging is available and targets the first debuggable page
- Query-based postconditions still depend on label/value matching when no stable DOM identifier is available
- `ghost_parse_screen` is intentionally treated as experimental until its schema and reliability are hardened
