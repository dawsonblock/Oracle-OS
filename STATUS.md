# Oracle OS Status

This status file is subordinate to [GOVERNANCE.md](GOVERNANCE.md). New subsystem work is expected to satisfy the governance contract before it is considered mature.

## Working
- MCP server and CLI entrypoints (`ghost mcp`, `setup`, `doctor`, `status`, `version`)
- 22 MCP tools are exposed
- AX-first perception tools: `ghost_context`, `ghost_state`, `ghost_find`, `ghost_read`, `ghost_inspect`, `ghost_element_at`, `ghost_screenshot`
- Action tools: `ghost_click`, `ghost_type`, `ghost_press`, `ghost_hotkey`, `ghost_scroll`, `ghost_focus`, `ghost_window`
- Recipe replay and CRUD for JSON recipes
- `ghost_ground` vision grounding through the sidecar
- Verified execution slice for `ghost_click`, `ghost_type`, `ghost_press`, and `ghost_focus`: pre/post observations, postcondition checks, JSONL trace output
- Runtime-managed post-execution graph and memory updates
- SQLite-backed graph persistence with trust-tier enforcement
- Project-memory drafts with canonical repo-local storage and episode-residue isolation
- Governance rule checking in the architecture layer
- Build-and-test CI workflow

## Partial
- `ghost_parse_screen` is wired to the vision sidecar, but its output contract is still experimental
- CDP fallback improves some Chrome flows, but it still depends on Chrome remote debugging being enabled
- Observation fusion now merges AX and Chrome CDP candidates conservatively, but full ranking and richer provenance are not in place yet
- Architecture review is advisory-first and not an autonomous blocker
- Project-memory promotion still requires explicit review; only draft writes are automated
- Recipes are replayable and agent-authored/manual-save only; trace-to-recipe induction does not exist yet

## Missing
- Promotion of sidecar `/detect` and `/parse` into fully supported Ghost runtime features
- Full workflow synthesis and promotion from reusable trace knowledge
- Trace-to-recipe induction, recipe validation, and recipe repair
- Full benchmark-driven release gating beyond `swift build` and `swift test`

## Known Failure Modes
- Deep AX tree walks in Chrome and Electron apps can still be slow or incomplete
- Some web inputs reject synthetic typing and require fallback behavior or URL-driven flows
- Vision features depend on a local sidecar plus model availability
- Chrome CDP enrichment currently only activates for Chrome-family flows and assumes the first debuggable page is the relevant tab
