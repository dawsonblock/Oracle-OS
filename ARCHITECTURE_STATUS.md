# Architecture Status

## Stable

- `GhostOS` Swift package and `ghost` executable naming
- 22-tool MCP surface
- AX-first perception and core action tools
- Recipe replay and CRUD for JSON recipes
- `ghost_ground` vision grounding

## Partial

- Canonical `Observation` snapshots now fuse AX with conservative Chrome CDP candidates
- Verified execution is active for `ghost_click`, `ghost_type`, `ghost_press`, and `ghost_focus`
- JSONL tracing exists for verified actions
- `ghost_parse_screen` is sidecar-backed, but the runtime still treats it as experimental

## Scaffold Only

- `Core/Policy`
- `Core/World`
- `Agent/Planning`
- `Agent/Skills`
- `Agent/Recovery`
- `Agent/Loop`
- `Learning/Memory`
- `Learning/Recipes`

## Not Started

- Bounded planner-driven operator loop in production use
- Integrated recipe induction, replay validation, and repair
- Benchmark harness and release-gating eval suite

## Known Failure Modes

- AX traversal can still be slow or sparse in deep browser and Electron trees
- Chrome CDP enrichment currently assumes Chrome remote debugging is available and targets the first debuggable page
- Query-based postconditions still depend on label/value matching when no stable DOM identifier is available
- `ghost_parse_screen` is intentionally treated as experimental until its schema and reliability are hardened
