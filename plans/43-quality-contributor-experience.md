# Plan 43: Contributor Experience

## Priority: MEDIUM
## Effort: Medium (1-2 days)
## Risk: Low — documentation and tooling only

## Problem

New contributors face a steep onboarding curve:
- No CONTRIBUTING.md
- No architecture overview diagram
- Build setup requires knowing stack + Haskell ecosystem
- No development container (devcontainer)
- No quick-start guide

## Implementation Plan

### Step 1: CONTRIBUTING.md

**File**: `CONTRIBUTING.md` (NEW)

Cover:
- Prerequisites (GHC, Stack, system deps)
- How to build (`make build`)
- How to test (`make test`)
- How to run specific tests (`make test-match PATTERN=...`)
- Code style requirements (link to CLAUDE.md)
- PR process
- Issue labels and priorities

### Step 2: Architecture overview

**File**: `docs/ARCHITECTURE.md` (NEW)

Include:
- Package dependency diagram (ASCII)
- Compilation pipeline stages
- Data flow: Source → Parse → Canonical → TypeCheck → Optimize → Generate
- Key data types at each stage
- Where to find things (module map)

### Step 3: Development container

**File**: `.devcontainer/devcontainer.json` (NEW)

```json
{
    "name": "Canopy Development",
    "image": "haskell:9.8",
    "postCreateCommand": "stack setup && make build",
    "customizations": {
        "vscode": {
            "extensions": [
                "haskell.haskell",
                "justusadam.language-haskell"
            ]
        }
    }
}
```

### Step 4: Makefile help target

**File**: `Makefile`

Add a `help` target that lists all available make commands:

```makefile
help:
	@echo "Available targets:"
	@echo "  build          - Build all packages"
	@echo "  test           - Run all tests"
	@echo "  test-unit      - Run unit tests only"
	@echo "  lint           - Run hlint"
	@echo "  format         - Format with ormolu"
	@echo "  clean          - Clean build artifacts"
```

### Step 5: First-time contributor issue labels

Create GitHub issue templates and labels:
- `good-first-issue` — simple, well-scoped tasks
- `help-wanted` — needs community contribution
- `documentation` — docs improvements
- `beginner-friendly` — includes mentoring notes

### Step 6: Quick-start script

**File**: `scripts/setup-dev.sh` (NEW)

One-command setup for new contributors:

```bash
#!/bin/bash
# Install dependencies, build, and run tests
stack setup
make build
make test
echo "Development environment ready!"
```

## Dependencies
- None
