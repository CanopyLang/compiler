# Architecture Decision Records

This document captures key architectural decisions made in the Canopy compiler.
Each record explains the context, the decision, and the trade-offs involved.
Entries are numbered chronologically and never deleted; superseded decisions
are marked as such.

---

## ADR-001: Separate AST Types Per Compiler Phase

**Date**: 2025-09-01
**Status**: Active
**Context**: The compiler needs intermediate representations between parsing
and code generation. A single shared AST would require optional fields and
runtime checks to enforce phase-specific invariants.

**Decision**: Use three distinct AST types:
- `AST.Source` -- direct representation of parsed syntax
- `AST.Canonical` -- names fully resolved, imports expanded
- `AST.Optimized` -- decision trees compiled, ready for codegen

Each phase consumes one type and produces the next.

**Consequences**:
- Invalid intermediate states are unrepresentable at the type level.
- Adding a new language construct requires updating all three AST types and
  the transformations between them.
- The explicit phase boundaries make it easy to test each phase in isolation.

---

## ADR-002: ByteString.Builder for Code Generation

**Date**: 2025-09-01
**Status**: Active
**Context**: The original Elm compiler used `[Char]` (Haskell `String`) in its
JavaScript generation pipeline, causing significant allocation overhead on
large modules.

**Decision**: All code generation paths use `Data.ByteString.Builder` to
construct output. `Generate.JavaScript.Builder` provides the JS AST builder
abstraction on top of it.

**Consequences**:
- 3-5x reduction in allocation during code generation compared to `String`.
- Builder composition is O(1), making large concatenations efficient.
- Source-level readability is lower than string-based approaches; mitigated
  by wrapping common patterns in named combinators.

---

## ADR-003: Hand-Written Recursive-Descent Parser

**Date**: 2025-09-01
**Status**: Active
**Context**: Parser generators (Happy, Megaparsec) add dependencies and make
error recovery harder to control. Elm's original parser was already
hand-written.

**Decision**: Keep the hand-written recursive-descent parser operating on
raw UTF-8 `ByteString` input. Parser combinators are defined in
`Parse.Primitives`.

**Consequences**:
- Full control over error messages and recovery strategies.
- No parser-generator dependency; simpler build.
- More boilerplate than a combinator library, but the boilerplate is
  straightforward and well-tested.
- Input size and nesting depth limits (`Parse.Limits`) are trivial to
  enforce because the parser is explicit about its recursion.

---

## ADR-004: Structured InternalError for Invariant Violations

**Date**: 2025-09-01
**Status**: Active (partially superseded by Plan 02)
**Context**: The original Elm compiler used raw `error` calls when hitting
supposedly impossible states. These produced unhelpful crash messages.

**Decision**: Replace bare `error` calls with `Reporting.InternalError.report`,
which produces a structured diagnostic including the file, module, and a
request to file a bug report. Plan 02 later converted many crash sites to
recoverable errors using `Reporting.Error.Internal`.

**Consequences**:
- Crashes produce actionable output that helps diagnose the root cause.
- Contributors can quickly locate the crash site from the diagnostic.
- Recoverable error variants (Plan 02) allow the compiler to continue and
  report multiple issues in a single run.

---

## ADR-005: Five-Package Layered Architecture

**Date**: 2025-09-15
**Status**: Active
**Context**: A monolithic compiler package creates long rebuild times and
makes it hard to enforce dependency boundaries between subsystems.

**Decision**: Split the compiler into five Stack packages with a strict
dependency DAG:

```
canopy-terminal -> canopy-builder -> canopy-driver -> canopy-query -> canopy-core
```

Dependencies flow downward only. This is enforced by
`scripts/check-package-dag.sh`.

**Consequences**:
- Changes to `canopy-core` do not force recompilation of the terminal.
- The build system, CLI, and compiler core can evolve independently.
- Cross-package imports require explicit `build-depends` declarations,
  preventing accidental coupling.

---

## ADR-006: Level-Based Parallel Compilation

**Date**: 2025-10-01
**Status**: Active
**Context**: Modules with no mutual dependencies can be compiled in parallel.
A fine-grained task graph is complex; a simpler approach groups modules by
dependency depth.

**Decision**: The driver (`canopy-driver`) uses `Worker.Pool` to compile
modules in parallel. Modules are stratified by dependency level: all modules
at level N are compiled concurrently, and level N+1 begins only after level
N completes.

**Consequences**:
- Simple to implement and reason about.
- Parallelism is bounded by the widest dependency level.
- The slowest module at any level gates the next level. Future work could
  adopt a finer-grained task graph if this becomes a bottleneck.

---

## ADR-007: Union-Find for Type Unification

**Date**: 2025-09-01
**Status**: Active
**Context**: Hindley-Milner type inference requires efficient unification of
type variables. Substitution-based approaches have O(n) per-lookup cost.

**Decision**: Use a mutable union-find data structure (`Type.UnionFind`) backed
by `IORef` for type variable equivalence classes. Path compression and
union-by-rank keep operations near O(1) amortized.

**Consequences**:
- Type inference is fast even on large modules.
- The mutable state requires `IO`, constraining where unification can be
  called.
- The occurs check (`Type.Occurs`) must traverse the find structure, adding
  a configurable depth limit to prevent stack overflow on pathological input.

---

## ADR-008: NOINLINE Name Constants for Sharing

**Date**: 2025-09-01
**Status**: Active
**Context**: The compiler frequently compares identifiers against well-known
names (`Int`, `Bool`, `Basics`, etc.). Creating these names on every
comparison wastes allocation.

**Decision**: All predefined name constants in `Canopy.Data.Name.Constants`
are marked `{-# NOINLINE #-}` so GHC allocates each one exactly once and
shares it across the entire process.

**Consequences**:
- Name comparisons against constants are pointer-equality fast when the
  runtime shares the thunk (which `NOINLINE` guarantees for CAFs).
- Adding a new built-in name requires a small boilerplate entry in
  `Constants.hs`.

---

## ADR-009: Global Logger via unsafePerformIO

**Date**: 2025-10-15
**Status**: Active
**Context**: Structured logging needs a single configuration point, but
threading a logger through every function signature is impractical in a
large codebase.

**Decision**: `Logging.Logger` initializes a global `IORef` via
`unsafePerformIO`. The logger is configured once at startup and read from
anywhere via `Logging.Logger.log`.

**Consequences**:
- Any module can emit structured log events without changing its signature.
- The `unsafePerformIO` usage is safe because the `IORef` is created once
  and only mutated during startup configuration.
- Testing must reset or override the logger; `Logging.Config` provides a
  `withLogConfig` bracket for this.

---

## ADR-010: Post-Optimization Simplification Pass

**Date**: 2025-11-01
**Status**: Active
**Context**: The main optimization pass (`Optimize.Expression`) focuses on
compiling pattern matches into decision trees and performing expression-level
transformations. Some algebraic simplifications (boolean short-circuit,
identity elimination, string folding, dead binding removal) are easier to
apply as a separate bottom-up pass after the main optimizer runs.

**Decision**: Add `Optimize.Simplify` as a post-optimization pass that walks
the `Opt.Expr` tree bottom-up and applies rewrite rules. It is invoked from
`Optimize.Module` after each definition is optimized.

**Consequences**:
- Simplification rules are centralized in one module, separate from the
  complex decision-tree logic.
- Each rule is independently testable (40 unit tests).
- The bottom-up walk ensures child expressions are simplified before parents,
  enabling cascading rewrites (e.g., `identity (if True then x else y)`
  simplifies to `x`).
- Common Subexpression Elimination (CSE) was intentionally deferred as a
  future enhancement due to the complexity of maintaining correct sharing
  semantics.

---

## ADR-011: Qualified Imports with Unqualified Types

**Date**: 2025-09-01
**Status**: Active
**Context**: Haskell import style significantly affects code readability.
Fully unqualified imports cause name collisions; fully qualified code is
verbose in type signatures.

**Decision**: Import types and type classes unqualified; import functions and
constructors qualified. Module aliases must be descriptive (`as Map`, not
`as M`).

**Consequences**:
- Type signatures read naturally: `Map ModuleName Module` instead of
  `Map.Map ModuleName.ModuleName Module.Module`.
- Function calls are unambiguous: `Map.insert`, `Map.lookup`.
- The convention is documented in `CLAUDE.md` and enforced during code review.

---

## ADR-012: Tasty Test Framework with Four Categories

**Date**: 2025-09-15
**Status**: Active
**Context**: The test suite needs unit tests, property tests, integration
tests, and golden (snapshot) tests. Different frameworks excel at each.

**Decision**: Use the Tasty test framework as the single runner, with:
- `tasty-hunit` for unit tests (`test/Unit/`)
- `tasty-quickcheck` for property tests (`test/Property/`)
- `tasty-hunit` for integration tests (`test/Integration/`)
- `tasty-golden` for golden tests (`test/Golden/`)

All test modules export a `tests :: TestTree` value and are registered in
`test/Main.hs`.

**Consequences**:
- A single `make test` command runs everything.
- Pattern-based filtering (`--pattern`) works across all test categories.
- Adding a new test module requires editing `test/Main.hs`, but this keeps
  the test tree explicit and prevents orphan tests.
