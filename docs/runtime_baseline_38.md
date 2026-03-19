# Runtime Baseline 38

## Environment

- Date: 2026-03-19
- Branch: `cursor/oracleos-runtime-upgrade-2079`
- Host OS: Linux (unsupported — Oracle-OS targets macOS 14+; see Package.swift `platforms`)

> **Note:** This baseline was captured in a Linux CI sandbox where the Swift
> toolchain is unavailable.  The package declares `macOS(.v14)` as its only
> supported platform (Package.swift), so a valid baseline should be re-captured
> on a macOS 14+ host with the Swift 6.0 toolchain.  The results below reflect
> the absence of the toolchain, not a build failure in the intended environment.

## Commands

```bash
swift package reset
swift build
swift test
```

## Results

### `swift package reset`

- Status: failed
- Exit code: 127
- Output: `swift: command not found`

### `swift build`

- Status: failed
- Exit code: 127
- Output: `swift: command not found`

### `swift test`

- Status: failed
- Exit code: 127
- Output: `swift: command not found`

## Build success/failure

- Build did not start because the Swift toolchain is unavailable in this environment.

## Test count

- Unknown. Tests did not start because the Swift toolchain is unavailable in this environment.

## Warnings

- None captured. The toolchain was missing before compilation or test discovery began.
