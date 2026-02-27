# Plan 29 — Split Remaining God Modules

**Priority:** Tier 5 (Hardening)
**Effort:** 3 days
**Risk:** Medium
**Files:** ~15 files created/modified

---

## Problem

After splitting `Reporting/Error/Syntax.hs` (Plan 07), 11 modules still exceed 1,000 lines:

| Lines | File | Proposed Split |
|-------|------|---------------|
| 2,034 | `Reporting/Error/Canonicalize.hs` | By error category (Import, Pattern, Type, Effect, Port) |
| 2,011 | `Reporting/Error/Type.hs` | By error category (Mismatch, InfiniteType, BadAnnotation) |
| 1,779 | `Json/Decode.hs` | Core decoder, combinators, JSON-specific decoders |
| 1,529 | `Type/Solve.hs` | Solver core, pool management, generalization, case branching |
| 1,144 | `Generate/JavaScript/Expression.hs` | By expression category (Literal, Function, Case, Let, Record) |
| 1,076 | `Test.hs` (terminal) | Test runner, browser setup, output formatting |
| 1,064 | `Http.hs` (builder) | HTTP client, archive handling, multipart, TLS |
| 1,050 | `Generate/JavaScript.hs` | Graph traversal, FFI generation, kernel generation |
| 1,029 | `Reporting/Exit.hs` (terminal) | By command (Make, Check, Repl, Install, Diff, Publish) |
| 1,004 | `Canonicalize/Module.hs` | Module header, imports, declarations, effects, FFI |
| 900 | `AST/Canonical.hs` | Types, effects, expressions, patterns |

## Implementation Strategy

### Priority 1: Error modules (same pattern as Plan 07)

**`Reporting/Error/Canonicalize.hs`** → split by error category:
- `Reporting/Error/Canonicalize/Import.hs`
- `Reporting/Error/Canonicalize/Pattern.hs`
- `Reporting/Error/Canonicalize/Type.hs`
- `Reporting/Error/Canonicalize/Effect.hs`
- `Reporting/Error/Canonicalize.hs` (re-exports)

**`Reporting/Error/Type.hs`** → split by error category:
- `Reporting/Error/Type/Mismatch.hs`
- `Reporting/Error/Type/Annotation.hs`
- `Reporting/Error/Type/Infinite.hs`
- `Reporting/Error/Type.hs` (re-exports)

**`Reporting/Exit.hs`** → split by command:
- `Reporting/Exit/Make.hs`
- `Reporting/Exit/Install.hs`
- `Reporting/Exit/Publish.hs`
- `Reporting/Exit.hs` (re-exports)

### Priority 2: Core compiler modules

**`Type/Solve.hs`** → split by responsibility:
- `Type/Solve.hs` (main entry, `run` function, ~200 lines)
- `Type/Solve/Pool.hs` (pool management, rank operations)
- `Type/Solve/Generalize.hs` (let generalization, variable extraction)
- `Type/Solve/CaseBranch.hs` (case branch isolation, cloning)
- `Type/Solve/Constraint.hs` (constraint dispatch)

**`Canonicalize/Module.hs`** → split by phase:
- `Canonicalize/Module.hs` (top-level orchestration)
- `Canonicalize/Module/Header.hs` (module header processing)
- `Canonicalize/Module/Imports.hs` (import resolution)
- `Canonicalize/Module/FFI.hs` (FFI loading and validation)

### Priority 3: Codegen and tooling

**`Generate/JavaScript/Expression.hs`** → split by expression category:
- `Generate/JavaScript/Expression.hs` (dispatch)
- `Generate/JavaScript/Expression/Literal.hs`
- `Generate/JavaScript/Expression/Function.hs`
- `Generate/JavaScript/Expression/Case.hs`
- `Generate/JavaScript/Expression/Record.hs`

**`Test.hs`** (terminal) → split by pipeline:
- `Test.hs` (entry point, `run`)
- `Test/Runner.hs` (test execution pipelines)
- `Test/Browser.hs` (Playwright setup and browser tests)
- `Test/Output.hs` (result formatting and reporting)

**`Http.hs`** (builder) → split by concern:
- `Http.hs` (public API)
- `Http/Client.hs` (HTTP GET/POST, TLS manager)
- `Http/Archive.hs` (archive download, integrity verification)
- `Http/Upload.hs` (multipart upload, publishing)

### For each split:

1. Create sub-modules with focused responsibilities
2. Make the parent module a thin re-export
3. Update `canopy-*.cabal` with new modules
4. Verify backward compatibility via re-exports
5. Run `make build && make test`

## Validation

```bash
make build && make test

# Verify no module exceeds 800 lines:
find packages -name "*.hs" -path "*/src/*" -exec wc -l {} + | sort -rn | head -20
```

## Acceptance Criteria

- No source module exceeds 1,000 lines
- Each sub-module has a single clear responsibility
- All re-exports preserve backward compatibility
- `make build && make test` passes
