# Ghost OS Progress

## Current State
- 22 MCP tools are exposed
- 21 tools are implemented today
- `ghost_parse_screen` is experimental and not yet implemented
- The recipe system is replay-first: JSON recipes can be run, listed, saved, and deleted, but there is no automatic recipe induction yet
- `ghost_click` and `ghost_type` now emit pre/post observations, verification metadata, and JSONL traces

## Working
- AX-first perception and action tools for desktop and browser workflows
- `ghost_ground` vision grounding through the local sidecar
- Wait polling for URL, title, element presence, focus, and value checks
- Replay of bundled recipes in `recipes/`

## In Progress
- Fused world-state contracts under `Sources/GhostOS/Core/`
- Runtime scaffolding for world state, policy, skills, planning, and loop control
- Trace-driven reliability infrastructure

## Not Yet Implemented
- Real full-screen `/detect` and `/parse` vision endpoints
- Autonomous executor loop with recovery orchestration
- Trace-to-recipe learning and recipe repair
- Benchmark harness and regression reporting
