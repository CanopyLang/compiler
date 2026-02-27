# Plan 04 — Write README.md and CONTRIBUTING.md

**Priority:** Tier 0 (Blocker)
**Effort:** 4 hours
**Risk:** None
**Files:** `README.md`, `CONTRIBUTING.md` (new files)

---

## Problem

The repo has no `README.md` at the root. Multiple internal documents (`CANOPY_PACKAGE_ECOSYSTEM_PLAN.md`, architecture docs) reference a `CONTRIBUTING.md` that does not exist. Without these files, the project is invisible to potential adopters and impenetrable to contributors.

## Implementation

### README.md Structure

```markdown
# Canopy

A compiled, pure functional language for reliable web applications.
Canopy extends Elm with JavaScript FFI, code splitting, and a built-in test runner.

## Quick Start

### Install from source
```
git clone https://github.com/<org>/canopy.git
cd canopy
stack install --fast
```

### Create a project
```
canopy init my-app
cd my-app
canopy reactor
```

## What Makes Canopy Different

- **JavaScript FFI** — Call JS functions with type-safe bindings via `foreign import javascript`
- **Code Splitting** — Automatic chunk splitting via `lazy import` for faster initial loads
- **Built-in Test Runner** — Unit, async, and browser tests with Playwright integration
- **Native Arithmetic** — Compile-time constant folding for numeric operations
- **Elm Compatible** — Reads `elm.json` projects, falls back to Elm package registry

## Commands

| Command | Description |
|---------|-------------|
| `canopy init` | Create a new project |
| `canopy make` | Compile to JavaScript |
| `canopy test` | Run test suite |
| `canopy repl` | Interactive session |
| `canopy reactor` | Development server |
| `canopy fmt` | Format source code |
| `canopy lint` | Static analysis |
| `canopy check` | Type-check without compiling |

## Project Structure

(Include the package layout from CLAUDE.md)

## Building from Source

### Prerequisites
- GHC 9.8.x (via Stack)
- Stack 2.x
- Node.js 18+ (for test runner)

### Build
```
make build
```

### Test
```
make test    # 2,376 tests
```

### Development
```
make lint    # hlint + ormolu
make format  # auto-format
```

## Documentation

- [Language Guide](docs/) (coming soon)
- [CLAUDE.md](CLAUDE.md) — Coding standards
- [Architecture](docs/architecture/) — Compiler internals

## License

(Match existing license)
```

### CONTRIBUTING.md Structure

```markdown
# Contributing to Canopy

## Getting Started

1. Fork and clone the repository
2. Install Stack: https://docs.haskellstack.org/
3. Build: `make build`
4. Test: `make test` (all 2,376 tests should pass)

## Development Workflow

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make changes following [CLAUDE.md](CLAUDE.md) standards
3. Run `make lint` and `make format`
4. Run `make test` — all tests must pass
5. Commit with conventional format: `feat(parser): add record wildcards`
6. Open a pull request

## Code Standards

All code must follow [CLAUDE.md](CLAUDE.md). Key requirements:
- Functions ≤ 15 lines
- ≤ 4 parameters per function
- Qualified imports (types unqualified, functions qualified)
- Lenses for record access/updates
- Haddock documentation on all exports
- No partial functions (head, tail, fromJust, !!, error)

## Package Structure

| Package | Purpose |
|---------|---------|
| `canopy-core` | Compiler: parsing, type checking, optimization, codegen |
| `canopy-query` | Query engine and parse caching |
| `canopy-driver` | Compilation orchestration |
| `canopy-builder` | Build system, dependency resolution, HTTP |
| `canopy-terminal` | CLI commands, test runner, REPL |

## Testing

- `make test` — Run all tests
- `make test-match PATTERN="Parser"` — Run matching tests
- `make test-unit` / `make test-property` / `make test-integration` / `make test-golden`

Tests must verify actual behavior, not implementation details.
See CLAUDE.md testing section for anti-patterns to avoid.

## Commit Messages

Follow conventional commits:
```
feat(parser): add support for record wildcards
fix(typecheck): handle recursive type aliases
perf(optimizer): improve dead code elimination
docs(api): add examples for Parser module
test(integration): add tests for .canopy file support
```

## Need Help?

Open an issue for questions about the codebase or contribution process.
```

### Step 1: Write README.md

Write the full README.md at the repo root, adapting the structure above with accurate details from the actual codebase (current command list, actual package structure, real prerequisites).

### Step 2: Write CONTRIBUTING.md

Write the full CONTRIBUTING.md at the repo root.

### Step 3: Update internal references

Search for references to a non-existent CONTRIBUTING.md and verify they now point correctly:

```bash
grep -r "CONTRIBUTING" docs/
```

## Validation

- Both files render correctly in GitHub markdown preview
- All links in the files resolve to real paths
- `make build && make test` unaffected

## Acceptance Criteria

- `README.md` exists at repo root with install, quickstart, commands, build instructions
- `CONTRIBUTING.md` exists at repo root with dev workflow, standards summary, testing instructions
- Internal doc references to CONTRIBUTING.md now resolve
