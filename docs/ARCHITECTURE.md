# Canopy Compiler Architecture

This document describes the high-level architecture of the Canopy compiler,
a fork of the Elm 0.19.1 compiler. It is intended for contributors who want
to understand how the pieces fit together before diving into source code.

## Package Dependency DAG

The compiler is split into five Stack packages with a strict layering:

```
                  canopy-terminal
                        |
                  canopy-builder
                        |
                  canopy-driver
                        |
                  canopy-query
                        |
                  canopy-core
```

Dependencies flow downward only. A package may depend on any package below
it in the diagram, but never on one above it. This invariant is enforced
by `scripts/check-package-dag.sh`.

### Package Responsibilities

| Package | Modules | Role |
|---------|--------:|------|
| **canopy-core** | 196 | Pure compiler logic: parsing, name resolution, type checking, optimization, code generation. No IO except through explicit parameters. |
| **canopy-query** | 3 | Query engine that wraps compiler passes with caching. Provides `Query.Engine` for demand-driven compilation and `Query.Simple` for single-module compilation with a global parse cache. |
| **canopy-driver** | 9 | Orchestrates multi-module compilation. Manages the worker pool (`Worker.Pool`), dispatches per-module queries (`Queries.*`), and assembles results. |
| **canopy-builder** | 24 | Build system and package management. Handles dependency resolution (`Build.*`), HTTP fetching (`Http.*`), package caching (`PackageCache.*`), the ELCO binary cache (`Compiler`), and cryptographic verification (`Crypto.*`). |
| **canopy-terminal** | 106 | CLI entry points: `Make`, `Install`, `Develop`, `Repl`, `Diff`, `Bump`, `Publish`, `Init`, `New`, `Lint`, `Fmt`, `Audit`. Also contains `CLI.*` for argument parsing and `Reporting.*` for user-facing error messages. |

## Compilation Pipeline

A single module flows through these stages:

```
  Source text (.can / .canopy file)
        |
        v
  [1] Parse          Parse.Module.parse
        |             Source text -> AST.Source.Module
        v
  [2] Canonicalize   Canonicalize.Module.canonicalize
        |             AST.Source.Module -> AST.Canonical.Module
        v
  [3] Type Check     Type.Constrain + Type.Solve
        |             AST.Canonical.Module -> Typed annotations
        v
  [4] Optimize       Optimize.Module.optimize
        |             AST.Canonical.Module -> AST.Optimized.Module
        v
  [5] Generate       Generate.JavaScript / Generate.Html
                      AST.Optimized.Module -> JavaScript / HTML output
```

### Stage Details

#### 1. Parsing

Location: `packages/canopy-core/src/Parse/`

The parser is a hand-written recursive-descent parser operating on UTF-8
`ByteString` input. It produces `AST.Source.Module` values.

Key modules:
- `Parse.Module` -- top-level module parsing
- `Parse.Expression` -- expression parsing (operators, lambdas, let, case, if)
- `Parse.Declaration` -- top-level declaration parsing
- `Parse.Type` -- type annotation parsing
- `Parse.Pattern` -- pattern parsing
- `Parse.Primitives` -- low-level parser combinators
- `Parse.String` -- string literal and escape handling
- `Parse.Limits` -- input size and depth limits

The parser enforces configurable depth limits (`Parse.Limits`) to prevent
stack overflow on adversarial input.

#### 2. Canonicalization (Name Resolution)

Location: `packages/canopy-core/src/Canonicalize/`

Resolves all names to their fully-qualified canonical forms. Detects
duplicate definitions, validates imports, and expands module aliases.

Key modules:
- `Canonicalize.Module` -- orchestrates canonicalization of a full module
- `Canonicalize.Expression` -- expression-level name resolution
- `Canonicalize.Pattern` -- pattern name resolution
- `Canonicalize.Type` -- type name resolution
- `Canonicalize.Environment` -- scope tracking

Input: `AST.Source.Module`
Output: `AST.Canonical.Module`

#### 3. Type Checking

Location: `packages/canopy-core/src/Type/`

Implements Hindley-Milner type inference with constraint generation and
solving. Uses a union-find data structure for efficient unification.

Key modules:
- `Type.Constrain.*` -- constraint generation from canonical AST
- `Type.Solve` -- constraint solver
- `Type.Unify` -- type unification algorithm
- `Type.UnionFind` -- union-find for type variable equivalence classes
- `Type.Instantiate` -- polymorphism instantiation
- `Type.Occurs` -- occurs check to prevent infinite types
- `Type.Error` -- type error formatting

The type checker includes an occurs check with configurable depth limits
to detect infinite types without unbounded recursion.

#### 4. Optimization

Location: `packages/canopy-core/src/Optimize/`

Transforms the canonical AST into an optimized form suitable for code
generation. The optimized AST (`AST.Optimized`) is a simpler
representation that has pattern matches compiled into decision trees.

Key modules:
- `Optimize.Module` -- module-level optimization entry point
- `Optimize.Expression` -- expression-level transformations
- `Optimize.DecisionTree` -- pattern match compilation (Maranget algorithm)
- `Optimize.Case` -- case expression optimization
- `Optimize.ConstantFold` -- constant folding for arithmetic
- `Optimize.Names` -- name mangling for codegen
- `Optimize.Port` -- port optimization

#### 5. Code Generation

Location: `packages/canopy-core/src/Generate/`

Produces JavaScript output from the optimized AST. Supports both
single-file output and code-split output with lazy-loaded chunks.

Key modules:
- `Generate.JavaScript` -- top-level JS generation
- `Generate.JavaScript.Expression` -- expression codegen
- `Generate.JavaScript.Builder` -- JS AST builder
- `Generate.JavaScript.Name` -- JS name generation
- `Generate.JavaScript.Kernel` -- kernel module embedding
- `Generate.JavaScript.CodeSplit.*` -- code splitting analysis and output
- `Generate.JavaScript.SourceMap` -- source map generation
- `Generate.JavaScript.Minify` -- minification
- `Generate.JavaScript.StringPool` -- string deduplication
- `Generate.Html` -- HTML page wrapper with CSP headers
- `Generate.Mode` -- dev vs. production mode

## Key Data Types

### AST Representations

The compiler uses three distinct AST representations, each with its own
module under `AST/`:

| Stage | Module | Key Types | Purpose |
|-------|--------|-----------|---------|
| Parsed | `AST.Source` | `Module`, `Expr`, `Pattern`, `Type` | Direct representation of source syntax |
| Canonical | `AST.Canonical` | `Module`, `Expr`, `Pattern`, `Type` | Names resolved, imports expanded |
| Optimized | `AST.Optimized` | `LocalGraph`, `GlobalGraph`, `Node`, `Expr` | Decision trees compiled, ready for codegen |

### Core Domain Types

| Type | Module | Purpose |
|------|--------|---------|
| `Name` | `Canopy.Data.Name` | Interned identifier (UTF-8) |
| `ModuleName.Canonical` | `Canopy.ModuleName` | Fully-qualified module name |
| `Package.Name` | `Canopy.Package` | Package author/project pair |
| `Version` | `Canopy.Version` | Semantic version (major.minor.patch) |
| `Region` | `Reporting.Annotation` | Source location (line, column) span |

## Build System

### Binary Cache (ELCO Format)

Compiled module interfaces are cached in a binary format with an ELCO
header:

```
bytes 0-3:   magic "ELCO" (4 bytes)
bytes 4-5:   schema version (Word16, big-endian)
bytes 6-7:   compiler major (Word16)
bytes 8-9:   compiler minor (Word16)
bytes 10-11: compiler patch (Word16)
bytes 12+:   payload (Binary-encoded)
```

The schema version is bumped whenever the binary format changes. Version
mismatches produce actionable error messages directing the user to rebuild.

### Dependency Resolution

The builder uses a constraint solver (`Build.*` in canopy-builder) to
resolve package dependencies. It fetches packages from the registry,
verifies cryptographic signatures, and caches them locally.

### Parallel Compilation

The driver (`canopy-driver`) manages a bounded worker pool
(`Worker.Pool`) that compiles modules in parallel. The pool respects a
configurable concurrency limit and uses the module dependency graph to
determine compilation order.

## Logging and Diagnostics

Location: `packages/canopy-core/src/Logging/`

The compiler uses structured logging with configurable sinks:

- `Logging.Logger` -- global logger (initialized once via `unsafePerformIO`)
- `Logging.Config` -- log level and sink configuration
- `Logging.Event` -- structured log event types
- `Logging.Sink` -- output destinations (stderr, file, null)

Error reporting uses rich diagnostic types:

- `Reporting.Diagnostic` -- structured diagnostics with error codes
- `Reporting.Doc` -- colorized terminal output builder
- `Reporting.Error.*` -- per-phase error types

## FFI System

Location: `packages/canopy-core/src/FFI/`

The FFI system allows Canopy modules to call JavaScript functions. FFI
declarations are validated against a manifest (`FFI.Manifest`) that
defines type signatures, and the validator (`FFI.Validator`) ensures
type safety at the boundary.

## Security Measures

- **Input size limits**: `Parse.Limits` caps source file size and nesting depth
- **Path traversal prevention**: All file paths are validated and normalized
- **CSP headers**: Generated HTML includes Content-Security-Policy meta tags
- **HTML escaping**: Attribute values in generated HTML are escaped
- **Package signatures**: Cryptographic verification of downloaded packages
- **Timing-safe comparison**: Used for signature verification

## File Layout Reference

```
packages/
  canopy-core/src/
    AST/               Abstract syntax tree definitions
    Canonicalize/      Name resolution
    Canopy/            Core types (Name, Version, Package, etc.)
    FFI/               Foreign function interface
    File/              File system operations
    Generate/          Code generation (JS, HTML)
    Json/              JSON encoding/decoding
    Logging/           Structured logging
    Optimize/          Optimization passes
    Parse/             Parser
    Reporting/         Error reporting and diagnostics
    Type/              Type inference and checking

  canopy-query/src/
    Query/             Query engine and parse caching

  canopy-driver/src/
    Queries/           Per-module compilation queries
    Worker/            Worker pool for parallel compilation

  canopy-builder/src/
    Build/             Build orchestration
    Builder/           Project builder
    Crypto/            Cryptographic operations
    Http/              HTTP client
    Interface/         Module interface types
    PackageCache/      Package cache management

  canopy-terminal/src/
    CLI/               Argument parsing
    Make/              Build command
    Install/           Package installation
    Develop/           Development server
    Repl/              Interactive REPL
    Diff/              Package diff
    Init/              Project initialization
    Lint/              Linter
    Publish/           Package publishing

test/
    Unit/              Per-function unit tests
    Property/          QuickCheck property tests
    Integration/       End-to-end pipeline tests
    Golden/            Output regression tests
```
