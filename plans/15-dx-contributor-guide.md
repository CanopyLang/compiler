# Plan 15: Contributor Onboarding & Architecture Guide

**Priority**: MEDIUM
**Effort**: Small (1 day)
**Risk**: Low
**Audit Finding**: No CONTRIBUTING.md, no architecture guide; new contributors must reverse-engineer the compilation pipeline

---

## Problem

A new contributor to Canopy has no guide explaining:
- How the compilation pipeline works
- Where to add a new feature
- How modules are organized
- What the testing strategy is
- How to run a subset of tests
- What the PR process looks like

The code is clean enough to read, but the roadmap is missing.

---

## Solution

Create comprehensive contributor documentation.

---

## Implementation

### Step 1: CONTRIBUTING.md

**File: `CONTRIBUTING.md`**

```markdown
# Contributing to Canopy

## Getting Started

### Prerequisites
- GHC 9.8+ (via ghcup or stack)
- Stack build tool
- Node.js 18+ (for LSP development)

### Building
```bash
git clone https://github.com/canopy-lang/canopy
cd canopy
make build       # Build all packages
make test        # Run all 3350+ tests
make lint        # Check code style
```

### Project Structure

```
canopy/
├── packages/
│   ├── canopy-core/     # Compiler: AST, parser, type checker, optimizer, codegen
│   ├── canopy-builder/  # Build system: dependency resolution, caching, parallelism
│   ├── canopy-terminal/ # CLI: commands, error display, REPL
│   ├── canopy-driver/   # Query engine for incremental compilation
│   ├── canopy-query/    # Caching and query interface
│   ├── canopy-webidl/   # WebIDL → Canopy binding generation
│   ├── canopy-lsp/      # Language server (TypeScript)
│   └── canopy-mcp/      # MCP server
├── test/                # Test suites
├── plans/               # Implementation plans
└── docs/                # Documentation
```

## Compilation Pipeline

Source file → JavaScript output:

```
1. PARSE         Parse.Module.parse : ByteString → Src.Module
                 ↓
2. CANONICALIZE   Canonicalize.Module.canonicalize : Src.Module → Can.Module
                 Names resolved, imports validated, effects checked
                 ↓
3. TYPE CHECK    Type.Constrain + Type.Solve : Can.Module → Annotations
                 HM type inference with let-polymorphism
                 ↓
4. OPTIMIZE      Optimize.Module.optimize : Can.Module + Annotations → Opt.Module
                 Decision trees, constant folding, dead code elimination
                 ↓
5. GENERATE      Generate.JavaScript : Opt.Module → Builder
                 JavaScript output with source maps
```

Each phase has its own AST type (Source → Canonical → Optimized).
Phases are in `packages/canopy-core/src/`.

## Common Tasks

### Adding a Language Feature

1. Add syntax to `Parse/Expression.hs` or `Parse/Declaration.hs`
2. Add AST constructors to `AST/Source.hs`
3. Handle in `Canonicalize/Expression.hs`
4. Add canonical constructors to `AST/Canonical/Types.hs`
5. Generate constraints in `Type/Constrain/Expression.hs`
6. Optimize in `Optimize/Expression.hs`
7. Generate JS in `Generate/JavaScript/Expression.hs`
8. Add tests at every level
9. Update golden tests

### Adding a CLI Command

1. Create `packages/canopy-terminal/src/YourCommand.hs`
2. Register in the CLI dispatcher
3. Add tests in `test/Unit/YourCommandTest.hs`

### Running Specific Tests

```bash
make test-match PATTERN="Parser"     # Tests matching "Parser"
make test-unit                        # Unit tests only
make test-property                    # Property tests only
make test-integration                 # Integration tests only
stack test --ta="--pattern JsGen"     # Golden tests for JS generation
```

## Code Standards

See CLAUDE.md for complete standards. Key rules:
- Functions ≤ 15 lines
- Qualified imports (types unqualified)
- No nested case expressions
- Lenses for record access
- Haddock documentation on all exports
- `where` preferred over `let`
- Parentheses preferred over `$`

## Pull Request Process

1. Create a branch: `feature/your-feature` or `fix/your-fix`
2. Make changes following CLAUDE.md
3. Run `make build && make test && make lint`
4. Commit with conventional format: `feat(parser): add record wildcards`
5. Open PR against `master`
6. All CI checks must pass
```

### Step 2: Architecture Decision Records

**File: `docs/architecture/DECISIONS.md`**

Document key architectural decisions:

```markdown
# Architecture Decision Records

## ADR-001: Separate AST Types Per Phase
**Decision**: Source, Canonical, and Optimized ASTs are separate types.
**Rationale**: Prevents invalid intermediate states. Each phase adds/removes information.
**Trade-off**: More boilerplate for conversions, but compile-time safety.

## ADR-002: ByteString-Based Code Generation
**Decision**: Code generation uses ByteString.Builder throughout.
**Rationale**: Eliminates String allocation in hot paths. 3-5x faster than [Char].
**Trade-off**: Less readable than String, but benchmarks justify it.

## ADR-003: Level-Based Parallel Compilation
**Decision**: Modules are compiled in parallel by dependency level.
**Rationale**: Maximizes parallelism while respecting dependency order.
**Trade-off**: Modules in the same level wait for the slowest. Could be improved with fine-grained dependency tracking.

## ADR-004: InternalError.report for Invariant Violations
**Decision**: Compiler invariant violations crash with structured diagnostics.
**Rationale**: Better than raw `error` calls. Provides bug report instructions.
**Trade-off**: Process terminates instead of recovering. Plan 02 addresses this.
```

---

## Validation

```bash
# Verify documentation renders
cat CONTRIBUTING.md | head -20  # Should show contributing guide

# Verify all referenced commands work
make build
make test
make lint
```

---

## Success Criteria

- [ ] CONTRIBUTING.md exists with getting started, pipeline overview, common tasks
- [ ] Architecture decision records document key design choices
- [ ] A new contributor can build, test, and make a PR following the guide
- [ ] All referenced `make` targets work
