# Ghost OS Status

## Working
- MCP server and CLI entrypoints (`ghost mcp`, `setup`, `doctor`, `status`, `version`)
- 22 MCP tools are exposed
- AX-first perception tools: `ghost_context`, `ghost_state`, `ghost_find`, `ghost_read`, `ghost_inspect`, `ghost_element_at`, `ghost_screenshot`
- Action tools: `ghost_click`, `ghost_type`, `ghost_press`, `ghost_hotkey`, `ghost_scroll`, `ghost_focus`, `ghost_window`
- Recipe replay and CRUD for JSON recipes
- `ghost_ground` vision grounding through the sidecar
- Verified execution slice for `ghost_click` and `ghost_type`: pre/post observations, postcondition checks, JSONL trace output

## Partial
- `ghost_parse_screen` is public for compatibility but remains experimental and not yet implemented
- CDP fallback improves some Chrome flows, but it still depends on Chrome remote debugging being enabled
- Observation fusion currently uses AX elements plus CDP/vision availability notes; real cross-source dedupe and ranking are not in place yet
- Policy, world state, planning, loop, and recovery types now exist as runtime scaffolding but are not driving autonomous execution yet
- Recipes are replayable and agent-authored/manual-save only; trace-to-recipe induction does not exist yet

## Missing
- Real `/detect` and `/parse` implementations in the vision sidecar
- Autonomous executor loop, planner-driven skills, and recovery orchestration
- Trace-to-recipe induction, recipe validation, and recipe repair
- Benchmark harness and reliability reporting suite

## Known Failure Modes
- Deep AX tree walks in Chrome and Electron apps can still be slow or incomplete
- Some web inputs reject synthetic typing and require fallback behavior or URL-driven flows
- Vision features depend on a local sidecar plus model availability
- Swift build and test validation requires Swift 6.2; this workspace currently reports Swift 6.1
