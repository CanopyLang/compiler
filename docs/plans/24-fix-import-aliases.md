# Plan 24 — Fix Import Alias Naming Conventions

**Priority:** Tier 4 (DX/Consistency)
**Effort:** 2 days
**Risk:** Low (mechanical renaming, no logic changes)
**Files:** ~60 files across all packages

---

## Problem

The CLAUDE.md mandates meaningful import aliases ("NOT abbreviations"). The codebase uses single-letter aliases pervasively:

| Alias | Used For | Should Be |
|-------|----------|-----------|
| `A` | `Reporting.Annotation` | `Annotation` |
| `I` | `Canopy.Interface` | `Interface` |
| `V` | `Canopy.Version` | `Version` |
| `D` | `Reporting.Doc` AND `Json.Decode` | `Doc` / `Decode` |
| `E` | `Json.Encode` AND `Reporting.Error.*` | `Encode` / `Error` |
| `P` | `Parse.Primitives` | `Primitives` or `Parse` |
| `N` | `Data.Name` | `Name` |
| `B` | `Data.ByteString.Builder` | `Builder` or `BB` |
| `M` | `Canopy.Magnitude` | `Magnitude` |
| `K` | `Canopy.Kernel` | `Kernel` |
| `W` | `Reporting.Warning` | `Warning` |
| `T` | `Canopy.Compiler.Type` | `CompilerType` |

The same alias letter refers to different modules in different files, making grep-based code navigation unreliable.

## Implementation

### Step 1: Define canonical alias map

Create a consistent alias mapping for the entire codebase:

```
Reporting.Annotation    → Annotation (or Ann)
Canopy.Interface        → Interface
Canopy.Version          → Version
Reporting.Doc           → Doc
Json.Decode             → Decode
Json.Encode             → Encode
Reporting.Error.Syntax  → SyntaxError
Reporting.Error.Type    → TypeError
Parse.Primitives        → Primitives
Data.Name               → Name
Data.ByteString.Builder → BB (standard Haskell convention)
Canopy.Magnitude        → Magnitude
Canopy.Kernel           → Kernel
Reporting.Warning       → Warning
Canopy.Compiler.Type    → CompilerType
Data.Foldable           → Foldable
```

### Step 2: Automated rename per file

For each file, use a systematic approach:

```bash
# Find all single-letter qualified imports
grep -rn "import qualified .* as [A-Z]$" packages/*/src/ | head -50
```

For each occurrence:
1. Identify the module being imported
2. Look up the canonical alias
3. Replace the alias in the import and all qualified uses

### Step 3: Process by module, not by alias

Do all files that import `Reporting.Annotation as A` at once:

```bash
# Find all files using "as A"
grep -rn "as A$" packages/*/src/
# In each file: replace "A." with "Annotation." and "as A" with "as Annotation"
```

Repeat for each single-letter alias.

### Step 4: Handle conflicts

Some files import multiple modules with the same target alias (e.g., both `Reporting.Doc` and `Json.Decode` currently use `D`). In these cases, use the more specific name:
- `Reporting.Doc as Doc`
- `Json.Decode as Decode`

### Step 5: Verify no regressions

```bash
make build && make test
```

The rename is purely syntactic — qualified names like `A.Region` become `Annotation.Region`. The compiled output is identical.

## Validation

```bash
make build && make test

# Verify no single-letter aliases remain:
grep -rn "import qualified .* as [A-Z]$" packages/*/src/
# Should return 0 results
```

## Acceptance Criteria

- Zero single-letter import aliases in any `packages/*/src/` file
- Every import alias is a meaningful name (≥3 characters)
- The same module always uses the same alias across the codebase
- `make build && make test` passes
