<p align="center">
  <img src="logo-animated.gif" width="140" alt="Ghost OS">
</p>

<h1 align="center">Ghost OS</h1>
<p align="center"><em>Full computer-use for AI agents.</em></p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black.svg" alt="macOS 14+">
  <img src="https://img.shields.io/badge/swift-6.2-orange.svg" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/MCP-compatible-green.svg" alt="MCP Compatible">
</p>

---

Your AI agent can write code, run tests, search files. But it can't click a button, send an email, or fill out a form. It lives inside a chat box.

Ghost OS changes that. One install, and any AI agent can see and operate every app on your Mac.

```
You:     "Send an email to sarah@company.com about the Q4 report"
Agent:   ghost_run recipe:"gmail-send" params:{recipient, subject, body}
         → Compose opens, fields fill, email sends. Done.
```

### Setup
![Ghost OS Setup Demo](demo.gif)

### Recipes in Action
Send emails and download papers. Any app. Any workflow.

![Ghost OS Recipes Demo](demo-recipes.gif)

### Beyond the Browser
Slack messages, Finder folders — Ghost OS operates native macOS apps, not just browsers.

![Ghost OS Slack + Finder Demo](demo-slack-finder.gif)

## Why Ghost OS?

Other computer-use tools take screenshots and guess what's on screen. Ghost OS reads the macOS accessibility tree — structured, labeled data about every element in every app. When the AX tree isn't enough (web apps, dynamic content), it falls back to a local vision model (ShowUI-2B) for visual grounding.

And when a workflow is encoded as a recipe, it can replay it. Other tools repeat the same expensive reasoning every time.

- **Replayable recipes** — Workflows live as JSON recipes that can be reviewed, reused, and shared.
- **Transparent** — Recipes are JSON. Read every step before running. No black box.
- **Native** — Accessibility tree first. Vision fallback when needed. Structured data over pixel guessing.
- **Any app** — Not just browsers. Slack, Finder, Messages — anything on your Mac.
- **Local** — Your data never leaves your machine.
- **Open** — MCP protocol. Works with Claude Code, Cursor, VS Code, or any MCP client.

| | | Ghost OS | Anthropic Computer Use | OpenAI Operator | OpenClaw |
|:---:|------|:--:|:--:|:--:|:--:|
| 👀 | **How it sees** | Accessibility tree + local VLM | Screenshots only | Screenshots only | Browser DOM |
| 🖥️ | **Native apps** | Any macOS app | Any (via pixels) | Browser only | Browser only |
| 🧠 | **Replayable workflows** | JSON recipes | No | No | No |
| 🔒 | **Data stays local** | Yes | Depends on setup | No (cloud) | Yes |
| 📖 | **Open source** | MIT | No | No | MIT |

## Install

```bash
brew install ghostwright/ghost-os/ghost-os
ghost setup
```

That's it. `ghost setup` handles permissions, MCP configuration, recipe installation, and vision model setup.

<details>
<summary>macOS beta? Use the manual install instead.</summary>

Homebrew has a known issue on macOS developer betas where it demands an Xcode version that doesn't exist yet. If `brew install` fails, install directly:

```bash
curl -sL https://github.com/ghostwright/ghost-os/releases/latest/download/ghost-os-2.0.6-macos-arm64.tar.gz | tar xz
sudo cp ghost /opt/homebrew/bin/
sudo cp ghost-vision /opt/homebrew/bin/
sudo mkdir -p /opt/homebrew/share/ghost-os
sudo cp GHOST-MCP.md /opt/homebrew/share/ghost-os/
sudo cp -r recipes /opt/homebrew/share/ghost-os/
sudo cp -r vision-sidecar /opt/homebrew/share/ghost-os/
ghost setup
```

</details>

## How It Works

Ghost OS connects to your AI agent through [MCP](https://modelcontextprotocol.io) and gives it 22 tools to see and operate your Mac. It reads the macOS accessibility tree for structured data about every app. For web apps where the AX tree falls short (Gmail, Slack), a local vision model (ShowUI-2B) finds elements visually. Click, type, scroll, press keys, manage windows. Any app, not just browsers.

```
You:     "Download the latest paper on chain-of-thought prompting from arXiv"
Agent:   ghost_run recipe:"arxiv-download" params:{query:"chain of thought prompting"}
         → Navigates to arXiv, searches, opens PDF, downloads to Desktop. Done.
```

Works with Claude Code, Cursor, VS Code, or anything that speaks MCP.

## Recipes

Recipes in Ghost OS are replayable JSON workflows. An agent or developer can author them, save them, and run them with parameters. Transparent and auditable.

**Today: replay and share recipes. Future learning and induction are not implemented yet.**

```bash
# One command sends an email
ghost_run recipe:"gmail-send" params:{"recipient":"hello@example.com","subject":"Hello","body":"World"}

# 7 steps, 30 seconds, 100% reliable
```

- Recipes are just JSON. Read every step before running.
- Share with your team. One person authors the workflow, everyone benefits.
- Chain recipes together. The agent knows when to call what.
- Author once with Claude or GPT-4. Replay with deterministic steps.

## 22 Tools

| | Tool | What it does |
|:---:|------|-------------|
| 🔍 | `ghost_context` | Get the current app, window title, URL, focused element, and all interactive elements on screen |
| 🔍 | `ghost_state` | List every running app with its windows, positions, and sizes |
| 🔍 | `ghost_find` | Search for elements by name, role, DOM id, or CSS class across the entire UI |
| 🔍 | `ghost_read` | Extract text content from any app, with depth control for nested content |
| 🔍 | `ghost_inspect` | Get complete metadata for one element: role, position, actions, DOM id, editable state |
| 🔍 | `ghost_element_at` | Identify what element is at a specific screen coordinate |
| 📸 | `ghost_screenshot` | Capture a window screenshot for visual debugging |
| 👁️ | `ghost_ground` | Find element coordinates using vision (ShowUI-2B). Works when AX tree can't find web elements |
| 👁️ | `ghost_parse_screen` | Experimental placeholder for full-screen vision parsing |
| 🎯 | `ghost_click` | Click an element by name, DOM id, or screen coordinates |
| ⌨️ | `ghost_type` | Type text into a specific field by name, or at the current cursor |
| ⌨️ | `ghost_press` | Press a single key like Return, Tab, Escape, or arrow keys |
| ⌨️ | `ghost_hotkey` | Press key combinations like Cmd+L, Cmd+Return, Cmd+Shift+P |
| 🎯 | `ghost_scroll` | Scroll up, down, left, or right in any app window |
| 🪟 | `ghost_focus` | Bring any app or specific window to the front |
| 🪟 | `ghost_window` | Minimize, maximize, close, move, or resize any window |
| ⏳ | `ghost_wait` | Wait for a URL change, element to appear or disappear, or title change |
| 📦 | `ghost_recipes` | List all installed recipes with descriptions and parameters |
| ▶️ | `ghost_run` | Execute a recipe with parameter substitution |
| 📦 | `ghost_recipe_show` | View the full steps and configuration of a recipe |
| 📦 | `ghost_recipe_save` | Install a new recipe from JSON |
| 📦 | `ghost_recipe_delete` | Remove an installed recipe |

## Diagnostics

```bash
$ ghost doctor

  [ok] Accessibility: granted
  [ok] Screen Recording: granted
  [ok] Processes: 1 ghost MCP process
  [ok] MCP Config: ghost-os configured
  [ok] Recipes: 4 installed
  [ok] AX Tree: 12/12 apps readable
  [ok] ghost-vision: /opt/homebrew/bin/ghost-vision
  [ok] ShowUI-2B model: ~/.ghost-os/models/ShowUI-2B (2.8 GB)
  [ok] Vision Sidecar: not running (auto-starts when needed)

  All checks passed. Ghost OS is healthy.
```

## Build From Source

```bash
git clone https://github.com/ghostwright/ghost-os.git
cd ghost-os
swift build
.build/debug/ghost setup
```

Requires Swift 6.2+ and macOS 14+.

## Architecture

```
AI Agent (Claude Code, Cursor, any MCP client)
    │
    │ MCP Protocol (stdio)
    │
Ghost OS MCP Server (Swift)
    │
    ├── Perception ──── see what's on screen (AX tree)
    ├── Vision ──────── visual grounding (ShowUI-2B, local)
    ├── Actions ─────── click, type, scroll, keys
    ├── Recipes ─────── replayable workflows
    └── AXorcist ────── macOS accessibility engine
```

~5,000 lines of Swift + Python vision sidecar. Built on [AXorcist](https://github.com/steipete/AXorcist) by [@steipete](https://github.com/steipete).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). We need recipes for more apps, testing on different setups, and bug reports. If you're building AI agents that do real things, this is the project.

## License

MIT
