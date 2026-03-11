# Oracle Controller

Oracle Controller is the native local operator console for Oracle OS.

## Components

- `OracleController`: SwiftUI macOS dashboard
- `OracleControllerHost`: local helper host that links `OracleOS` and owns runtime execution
- `OracleControllerShared`: typed IPC models shared by the app and the host
- `OracleController.xcworkspace`: Xcode workspace entry point

## What It Does

- live snapshot-based monitor for the current app
- manual action control for focus, click, type, press, scroll, and wait
- recipe library with create, duplicate, edit, save, delete, and run
- trace session browser with per-step verification, hashes, and artifact links
- health panel for permissions, sidecar state, trace directory, and recipe directory

## Runtime Model

- one controller app launch starts one local host process
- one host process owns one runtime trace session
- the UI never calls heavy OracleOS APIs directly
- verified actions and recipe runs flow through `OracleControllerHost`
- trace data comes from repo-local `.traces/`

## Opening It

### In Xcode

```bash
open OracleController.xcworkspace
```

Run the `OracleController` scheme. The host target is built alongside it.

### From SwiftPM

```bash
swift build
./.build/debug/OracleController
```

If the controller cannot locate the host binary automatically, set:

```bash
export ORACLE_CONTROLLER_HOST_PATH="$PWD/.build/debug/OracleControllerHost"
```

## Notes

- The controller is local-only and human-supervised.
- Risky actions still require explicit confirmation in the UI.
- Monitoring is low-frequency snapshot refresh, not streaming video.
- The app uses the existing recipe JSON schema and does not change MCP tool names.
