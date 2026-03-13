#!/usr/bin/env python3
"""Architecture guard for Oracle-OS.

Scans Swift source files for forbidden imports that would violate
the architectural boundary rules defined in GOVERNANCE.md and
ARCHITECTURE_GOVERNANCE.md.

Prevents:
- AgentLoop absorbing subsystem internals (Rule 2)
- Planner absorbing subsystem internals (Rule 3)
"""

import os
import sys

FORBIDDEN_IMPORTS = {
    "AgentLoop.swift": [
        "GraphScorer",
        "WorkflowSynthesizer",
        "PatchRanker",
        "DOMIndexer",
        "BrowserTargetResolver",
        "MemoryPromotion",
    ],
    "Planner.swift": [
        "RepoGraphBuilder",
        "WorkflowSynthesizer",
        "PatchApplier",
        "DirectExecutor",
        "DOMParser",
    ],
}


def scan_file(path):
    with open(path) as f:
        text = f.read()

    violations = []

    name = os.path.basename(path)

    if name in FORBIDDEN_IMPORTS:
        for item in FORBIDDEN_IMPORTS[name]:
            if item in text:
                violations.append(item)

    return violations


def scan_repo(root):
    violations = []

    for dirpath, _, files in os.walk(root):
        for file in files:
            if file.endswith(".swift"):
                path = os.path.join(dirpath, file)
                v = scan_file(path)

                if v:
                    violations.append((path, v))

    return violations


if __name__ == "__main__":
    root = "Sources"

    if not os.path.isdir(root):
        print("Sources directory not found, skipping architecture guard.")
        sys.exit(0)

    violations = scan_repo(root)

    if violations:
        print("\nARCHITECTURE VIOLATIONS FOUND\n")

        for path, items in violations:
            print(path)
            for item in items:
                print("  forbidden:", item)

        sys.exit(1)

    print("Architecture guard passed.")
