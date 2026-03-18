# Implementation Plan: Structured Debug Logging System

## Scope

Replace the three existing logging systems (`Logging.Debug`, `Debug.Logger`, `Logging.Logger`) with a single unified, type-safe, structured logging system. Every logging call site across the entire codebase gets migrated.

Reference design: `docs/STRUCTURED_LOGGING_DESIGN.md`

---

## Inventory of All Call Sites

### System 1: `Debug.Logger` (canopy-query) — `CANOPY_DEBUG` env var

| # | File | Calls | Categories Used |
|---|------|-------|-----------------|
| 1 | `canopy-driver/src/Driver.hs` | 20 | COMPILE_DEBUG, FFI_DEBUG, CACHE_DEBUG |
| 2 | `canopy-driver/src/Queries/Parse/Module.hs` | 6 | PARSE |
| 3 | `canopy-driver/src/Queries/Type/Check.hs` | 13 | TYPE |
| 4 | `canopy-driver/src/Queries/Canonicalize/Module.hs` | 10 | TYPE |
| 5 | `canopy-driver/src/Queries/Optimize.hs` | 10 | COMPILE_DEBUG |
| 6 | `canopy-driver/src/Queries/Generate.hs` | 9 | CODEGEN |
| 7 | `canopy-driver/src/Queries/Kernel.hs` | 16 | KERNEL_DEBUG |
| 8 | `canopy-driver/src/Queries/Foreign.hs` | 7 | FFI_DEBUG |
| 9 | `canopy-driver/src/Worker/Pool.hs` | 13 | WORKER_DEBUG |
| 10 | `canopy-query/src/Query/Engine.hs` | 10 | QUERY_DEBUG, CACHE_DEBUG |
| 11 | `canopy-builder/src/Compiler.hs` | 32 | COMPILE_DEBUG |

**Subtotal: 146 calls across 11 files**

### System 2: `Logging.Debug` (canopy-core) — `CANOPY_LOG` env var

| # | File | Calls | Categories Used |
|---|------|-------|-----------------|
| 12 | `canopy-builder/src/Builder.hs` | 17 | BUILD |
| 13 | `canopy-builder/src/Builder/State.hs` | 3 | BUILD |
| 14 | `canopy-builder/src/Builder/Incremental.hs` | 7 | BUILD |
| 15 | `canopy-builder/src/Builder/Hash.hs` | 1 | BUILD |
| 16 | `canopy-builder/src/Interface/JSON.hs` | 3 | BUILD |

**Subtotal: 31 calls across 5 files**

### System 3: `Logging.Logger` (canopy-core, disabled) — no-op

| # | File | Calls | Functions |
|---|------|-------|-----------|
| 17 | `canopy-terminal/src/Make.hs` | 5 | setLogFlag, printLog |
| 18 | `canopy-terminal/src/Check.hs` | 1 | setLogFlag |
| 19 | `canopy-terminal/src/Publish.hs` | 1 | printLog |
| 20 | `canopy-terminal/src/Make/Environment.hs` | 1 | setLogFlag |
| 21 | `canopy-terminal/src/Make/Generation.hs` | 4 | printLog |
| 22 | `canopy-terminal/src/Make/Output.hs` | 7 | printLog |
| 23 | `canopy-core/src/File/Package.hs` | 7 | Logger.printLog |
| 24 | `canopy-core/src/File/Archive.hs` | 21 | Logger.printLog |

**Subtotal: 47 calls across 8 files**

### Old/legacy code (not migrated — just deleted or left alone)

| File | Calls | Notes |
|------|-------|-------|
| `old/builder/src/Canopy/Details.hs` | 155 | Legacy, in old/ directory |
| `old/builder/src/Deps/Solver.hs` | 39 | Legacy, in old/ directory |
| `old/builder/src/Build/Paths.hs` | 5 | Legacy, in old/ directory |
| `old/builder/src/Compile.hs` | 3 | Legacy, in old/ directory |
| `old/builder/src/Build/Module/Compile.hs` | 5 | Legacy, in old/ directory |

**These are in `old/` — no migration needed. They reference the old modules but are not compiled.**

### Logging module files to replace/delete

| File | Action |
|------|--------|
| `canopy-core/src/Logging/Debug.hs` (332 lines) | Replace with new modules |
| `canopy-core/src/Logging/Logger.hs` (22 lines) | Delete |
| `canopy-query/src/Debug/Logger.hs` (~120 lines) | Delete |

---

## Package Dependency Constraint

```
canopy-core          (foundation — no deps on other canopy packages)
  ↑
canopy-query         (depends on canopy-core)
  ↑
canopy-driver        (depends on canopy-core, canopy-query)
  ↑
canopy-builder       (depends on canopy-core, canopy-query, canopy-driver)
  ↑
canopy-terminal      (depends on all above)
```

The new logging modules **must live in canopy-core** since all packages depend on it. This is where `Logging.Debug` already lives. The `aeson` dependency already exists in canopy-core.

---

## Phase 1: Create Foundation Modules in canopy-core

### Step 1.1: Create `Logging/Event.hs`

**New file**: `packages/canopy-core/src/Logging/Event.hs`

Contains:
- `LogLevel` (TRACE, DEBUG, INFO, WARN, ERROR) — reuse existing names
- `Phase` (PhaseParse, PhaseCanon, PhaseTypeConstrain, PhaseTypeSolve, PhaseOptimize, PhaseGenerate, PhaseBuild, PhaseCache, PhaseFFI, PhaseWorker, PhaseKernel)
- `Duration` newtype (microseconds)
- All stats records: `ParseStats`, `CanonStats`, `TypeStats`, `OptStats`, `GenStats`, `CompileStats`
- `LogEvent` ADT with all constructors (see design doc Section 3)
- `eventLevel :: LogEvent -> LogLevel`
- `eventPhase :: LogEvent -> Phase`
- `renderEventCLI :: LogEvent -> String` — human-readable one-line summary
- Full Haddock on every export

**Depends on**: `Data.Name`, `Canopy.ModuleName`, `Data.Map`, `Data.Text`

**Estimated size**: ~250 lines

### Step 1.2: Create `Logging/Config.hs`

**New file**: `packages/canopy-core/src/Logging/Config.hs`

Contains:
- `LogConfig` record:
  ```haskell
  data LogConfig = LogConfig
    { _configEnabled :: !Bool
    , _configLevel :: !LogLevel
    , _configPhases :: ![Phase]     -- empty = all phases
    , _configFormat :: !OutputFormat -- CLI | JSON
    , _configFile :: !(Maybe FilePath)
    }
  ```
- `OutputFormat` (CLI | JSON)
- `parseLogConfig :: IO LogConfig` — reads env vars
- `readConfig :: IO LogConfig` — cached IORef read
- `shouldEmit :: LogConfig -> LogEvent -> Bool` — level + phase filter
- Env var parsing:
  - `CANOPY_LOG` — primary (e.g., `1`, `DEBUG`, `DEBUG:PARSE,TYPE`)
  - `CANOPY_DEBUG` — alias for backwards compatibility (if `CANOPY_LOG` not set, falls back to this)
  - `CANOPY_LOG_LEVEL` — override level
  - `CANOPY_LOG_FORMAT` — `cli` (default) or `json`
  - `CANOPY_LOG_FILE` — optional file path
- `{-# NOINLINE configRef #-}` IORef via `unsafePerformIO`

**Depends on**: `Logging.Event`, `System.Environment`, `Data.IORef`, `System.IO.Unsafe`

**Estimated size**: ~180 lines

### Step 1.3: Create `Logging/Sink.hs`

**New file**: `packages/canopy-core/src/Logging/Sink.hs`

Contains:
- `Sink` type: `newtype Sink = Sink { runSink :: LogEvent -> IO () }`
- `cliSink :: IO.Handle -> Sink` — formatted `[timestamp] [LEVEL] [phase] message` to handle
- `jsonSink :: IO.Handle -> Sink` — one JSON object per line (NDJSON)
- `fileSink :: FilePath -> IO Sink` — opens file handle, returns sink
- `nullSink :: Sink` — `Sink (const (pure ()))`
- `combineSinks :: [Sink] -> Sink` — fan-out to multiple sinks
- CLI rendering uses `Reporting.Doc` for color (green for INFO, yellow for WARN, red for ERROR, dim for TRACE/DEBUG)
- JSON rendering uses `Data.Aeson` (already in canopy-core deps)
- Timestamp via `Data.Time`

**Depends on**: `Logging.Event`, `Data.Aeson`, `Data.Time`, `System.IO`, `Reporting.Doc`

**Estimated size**: ~200 lines

### Step 1.4: Create `Logging/Metrics.hs`

**New file**: `packages/canopy-core/src/Logging/Metrics.hs`

Contains:
- `timed :: IO a -> IO (a, Duration)` — wall-clock timing using `Data.Time.Clock`
- `MetricsSummary` record (total duration, per-phase durations, cache hit/miss counts)
- This is a small utility module

**Depends on**: `Logging.Event` (for `Duration`, `Phase`), `Data.Time`

**Estimated size**: ~50 lines

### Step 1.5: Create `Logging/Logger.hs` (replaces old `Logging/Logger.hs`)

**Replaces**: `packages/canopy-core/src/Logging/Logger.hs` (currently a 22-line no-op)

Contains:
- `logEvent :: LogEvent -> IO ()` — main entry point: reads config, checks shouldEmit, dispatches to sinks
- `logEvents :: [LogEvent] -> IO ()` — batch flush for pure-phase accumulated events
- `withTiming :: Phase -> IO a -> IO (a, Duration)` — timed wrapper that also emits PhaseEnter/PhaseExit events
- `isEnabled :: IO Bool` — quick check (for call sites that want to skip expensive payload construction)
- Sink initialization based on config (done once, cached alongside config)

**Backward compatibility**: Also export `printLog` and `setLogFlag` as deprecated wrappers:
```haskell
-- | Deprecated. Use 'logEvent' instead.
printLog :: String -> IO ()
printLog msg = logEvent (BuildLogLegacy msg)

-- | Deprecated. No-op. Use CANOPY_LOG env var instead.
setLogFlag :: Bool -> IO ()
setLogFlag _ = pure ()
```

This means the 47 `Logging.Logger` call sites (System 3) **keep compiling immediately** with no changes needed. We migrate them properly in Phase 4.

**Depends on**: `Logging.Event`, `Logging.Config`, `Logging.Sink`, `Logging.Metrics`

**Estimated size**: ~120 lines

### Step 1.6: Update `canopy-core.cabal`

- Replace `Logging.Logger` entry (already exists, module is being rewritten)
- Replace `Logging.Debug` entry (will be rewritten in Phase 3)
- Add new entries: `Logging.Event`, `Logging.Config`, `Logging.Sink`, `Logging.Metrics`

### Step 1.7: Add `BuildLogLegacy` constructor to `LogEvent`

For backward compat with the 47 `printLog` call sites:

```haskell
  -- Legacy / unstructured
  | BuildLogLegacy  !String   -- ^ Legacy printLog message (deprecated)
```

This lets us keep the old API compiling while we systematically migrate each call to a proper typed event.

### Validation checkpoint

```bash
make build   # zero warnings
make test    # all 1503 tests pass
```

At this point: new modules exist, old `Logging.Logger` is replaced with new version that preserves the old API, `Logging.Debug` still exists unchanged. No external behavior changes.

---

## Phase 2: Create Compatibility Shim for `Debug.Logger`

### Step 2.1: Rewrite `Debug.Logger` to delegate to `Logging.Logger`

**Modify**: `packages/canopy-query/src/Debug/Logger.hs`

Keep the exact same API (`debug`, `debugIO`, `isDebugEnabled`, `shouldLog`, `DebugCategory(..)`) but internally delegate to the new system:

```haskell
debug :: DebugCategory -> String -> IO ()
debug category message =
  Logger.logEvent (categoryToEvent category message)

categoryToEvent :: DebugCategory -> String -> LogEvent
categoryToEvent PARSE msg        = ParseLogLegacy msg
categoryToEvent TYPE msg         = TypeLogLegacy msg
categoryToEvent CODEGEN msg      = GenerateLogLegacy msg
categoryToEvent COMPILE_DEBUG msg = CompileLogLegacy msg
categoryToEvent CACHE_DEBUG msg  = CacheLogLegacy msg
categoryToEvent QUERY_DEBUG msg  = QueryLogLegacy msg
categoryToEvent WORKER_DEBUG msg = WorkerLogLegacy msg
categoryToEvent KERNEL_DEBUG msg = KernelLogLegacy msg
categoryToEvent FFI_DEBUG msg    = FFILogLegacy msg
-- ... etc
```

This requires adding `*LogLegacy` constructors to `LogEvent`:

```haskell
  -- Legacy string-based events (from Debug.Logger migration)
  | ParseLogLegacy     !String
  | TypeLogLegacy      !String
  | CanonLogLegacy     !String
  | CompileLogLegacy   !String
  | CacheLogLegacy     !String
  | QueryLogLegacy     !String
  | WorkerLogLegacy    !String
  | KernelLogLegacy    !String
  | FFILogLegacy       !String
  | GenerateLogLegacy  !String
  | BuildLogLegacy     !String
  | PermissionsLogLegacy !String
  | DepsSolverLogLegacy !String
```

These are temporary — each gets replaced with a proper typed event when we migrate the call site in Phase 3.

### Step 2.2: Update `Debug.Logger` env var handling

- `Debug.Logger` currently reads `CANOPY_DEBUG`
- After this change it delegates to `Logging.Logger` which reads `CANOPY_LOG` (with `CANOPY_DEBUG` fallback)
- Remove the `unsafePerformIO` `enabledCategories` from `Debug.Logger` — no longer needed since config is centralized

### Step 2.3: Update `canopy-query.cabal`

Add `canopy-core` dependency — already exists. No changes needed.

### Validation checkpoint

```bash
make build   # zero warnings
make test    # all 1503 tests pass
# Manual test:
CANOPY_LOG=DEBUG:PARSE canopy make   # should see parse events
CANOPY_DEBUG=1 canopy make           # backward compat — should still work
```

At this point: all 146 `Debug.Logger` call sites and all 47 `Logging.Logger` call sites go through the new unified system. `Logging.Debug` users (31 calls) still use the old system directly.

---

## Phase 3: Migrate `Debug.Logger` Call Sites to Typed Events

For each file, replace `Logger.debug CATEGORY "string message"` with `Log.logEvent (TypedConstructor args)`.

### Step 3.1: Migrate `Queries/Parse/Module.hs` (6 calls)

**File**: `packages/canopy-driver/src/Queries/Parse/Module.hs`

| Old Call | New Event |
|----------|-----------|
| `Logger.debug PARSE ("Starting parse query for: " ++ path)` | `Log.logEvent (ParseStarted path (BS.length content))` |
| `Logger.debug PARSE ("File size: " ++ show (BS.length content) ++ " bytes")` | (merged into ParseStarted above) |
| `Logger.debug PARSE ("Parse success: module " ++ show name)` | `Log.logEvent (ParseCompleted path stats)` |
| `Logger.debug PARSE ("Declarations: " ++ show n)` | (merged into ParseCompleted stats) |
| `Logger.debug PARSE ("Imports: " ++ show n)` | (merged into ParseCompleted stats) |
| `Logger.debug PARSE ("Foreign imports: " ++ show n)` | (merged into ParseCompleted stats) |

Replace import `Debug.Logger` with `Logging.Logger`. Remove `logModuleInfo` helper (subsumed by `ParseStats`). Remove `countDeclarations` helper (inline into stats construction).

**Net effect**: 6 string log calls → 2 typed events. Helpers removed. File shrinks.

### Step 3.2: Migrate `Queries/Type/Check.hs` (13 calls)

**File**: `packages/canopy-driver/src/Queries/Type/Check.hs`

| Old Call | New Event |
|----------|-----------|
| `Logger.debug TYPE ("Starting type checking for: " ++ show modName)` | `Log.logEvent (TypeConstrainStarted modName)` |
| `logModuleStructure canonical` (3 debug calls inside) | `Log.logEvent (CanonStatsEvent modName stats)` or inline |
| `Logger.debug TYPE "Generating type constraints"` | (merged into TypeConstrainStarted) |
| `logConstraintInfo constraint` (stub: just "Constraints generated") | Remove entirely — real constraint logging comes in Phase 6 |
| `Logger.debug TYPE "Running type solver"` | `Log.logEvent (TypeSolveStarted modName constraintCount)` |
| `Logger.debug TYPE ("Type checking failed: " ++ show (countErrors errors))` | `Log.logEvent (TypeSolveFailed modName errorCount)` |
| `logTypeErrors errors` (iterates and logs each error) | Keep but convert to `Log.logEvents` batch |
| `Logger.debug TYPE ("Type checking success: " ++ show ...)` | `Log.logEvent (TypeSolveCompleted modName stats)` |
| `logTypedBindings typeMap` (iterates and logs each binding) | Remove — TRACE-level, add back in Phase 6 |

Remove: `logModuleStructure`, `logConstraintInfo` (stub), `logTypedBindings`, `logBinding`, `logSingleError`, `countErrors`, `describeEffects`. These are all string-formatting helpers that become unnecessary.

**Net effect**: 13 string calls + 6 helpers → 4 typed events. Major cleanup.

### Step 3.3: Migrate `Queries/Canonicalize/Module.hs` (10 calls)

**File**: `packages/canopy-driver/src/Queries/Canonicalize/Module.hs`

Replace all `Logger.debug TYPE` calls with:
- `Log.logEvent (CanonStarted modName)` at entry
- `Log.logEvent (CanonCompleted modName stats)` on success
- `Log.logEvent (CanonFailed modName errorText)` on failure

Remove string-formatting helpers.

### Step 3.4: Migrate `Queries/Optimize.hs` (10 calls)

**File**: `packages/canopy-driver/src/Queries/Optimize.hs`

| Old | New |
|-----|-----|
| `Logger.debug COMPILE_DEBUG ("Optimize: Starting for module: " ++ ...)` | `Log.logEvent (OptimizeStarted modName)` |
| `Logger.debug COMPILE_DEBUG ("Optimize: Success with " ++ ...)` | `Log.logEvent (OptimizeCompleted modName stats)` |
| `Logger.debug COMPILE_DEBUG ("Optimize: Failed with error: " ++ ...)` | `Log.logEvent (OptimizeFailed modName errorText)` |
| `logWarning _warning = debug COMPILE_DEBUG "  - <warning>"` | Remove stub entirely |
| `logOptimizationStats` (3 debug calls) | Merged into `OptimizeCompleted` stats |

Remove: `logWarnings`, `logWarning` (stub), `logOptimizationStats`, `isJust` helper.

### Step 3.5: Migrate `Queries/Generate.hs` (9 calls)

Replace with `GenerateStarted`, `GenerateCompleted`, `GenerateStats`.

### Step 3.6: Migrate `Queries/Kernel.hs` (16 calls)

Replace with `KernelStarted`, `KernelCompleted`, `KernelFailed` events. Add these constructors to `LogEvent`:

```haskell
  | KernelStarted    !FilePath
  | KernelCompleted  !FilePath !Int    -- bytes
  | KernelFailed     !FilePath !Text
```

### Step 3.7: Migrate `Queries/Foreign.hs` (7 calls)

Replace with `FFILoading`, `FFILoaded`, `FFIMissing` events (already in design).

### Step 3.8: Migrate `Worker/Pool.hs` (13 calls)

Replace with `WorkerSpawned`, `WorkerCompleted`, `WorkerFailed` events (already in design). Add:

```haskell
  | WorkerPoolCreated !Int    -- pool size
  | WorkerPoolShutdown
```

### Step 3.9: Migrate `Query/Engine.hs` (10 calls)

Replace with `CacheHit`, `CacheMiss`, `CacheEvict` events (already in design). Add:

```haskell
  | QueryExecuted   !String !Duration  -- query description, time
  | QueryCached     !String            -- query description
```

### Step 3.10: Migrate `Driver.hs` (20 calls)

Replace with `CompileStarted`, `CompilePhaseEnter`, `CompilePhaseExit`, `CompileCompleted`, `CompileFailed` events. Use `Log.withTiming` around phase calls.

### Step 3.11: Migrate `canopy-builder/src/Compiler.hs` (32 calls)

This is the largest single file. Replace all `Logger.debug COMPILE_DEBUG "..."` with appropriate typed events. Many of these are build-orchestration messages — add:

```haskell
  | BuildStarted       !FilePath
  | BuildModuleStarted !ModuleName
  | BuildModuleCompleted !ModuleName !Duration
  | BuildCompleted      !Int !Duration  -- module count, total time
  | BuildFailed         !Text
```

### Validation checkpoint

```bash
make build   # zero warnings
make test    # all 1503 tests pass
CANOPY_LOG=DEBUG canopy make   # verify typed output
```

At this point: all 146 `Debug.Logger` call sites are migrated to typed events. The `*LogLegacy` constructors from Phase 2 are no longer used by any `Debug.Logger` consumer (only by `Logging.Logger.printLog` backward compat).

---

## Phase 4: Migrate `Logging.Debug` Call Sites (canopy-builder)

### Step 4.1: Migrate `Builder.hs` (17 calls)

Replace `Logger.debug BUILD "..."` with typed events. These are build-system events:

```haskell
  | BuildPhaseStarted   !Text          -- phase description
  | BuildDepsResolved   !Int           -- dependency count
  | BuildGraphConstructed !Int !Int    -- node count, edge count
```

### Step 4.2: Migrate `Builder/State.hs` (3 calls)

Replace with `BuildStateUpdated` events.

### Step 4.3: Migrate `Builder/Incremental.hs` (7 calls)

Replace with:
```haskell
  | IncrementalCheckStarted
  | IncrementalCacheHit   !ModuleName
  | IncrementalCacheMiss  !ModuleName
  | IncrementalCompleted  !Int !Int    -- hits, misses
```

### Step 4.4: Migrate `Builder/Hash.hs` (1 call)

Replace with `BuildHashComputed` event.

### Step 4.5: Migrate `Interface/JSON.hs` (3 calls)

Replace with interface-related events:
```haskell
  | InterfaceLoaded   !FilePath
  | InterfaceSaved    !FilePath
  | InterfaceFailed   !FilePath !Text
```

### Validation checkpoint

```bash
make build && make test
```

---

## Phase 5: Migrate `Logging.Logger` Call Sites (legacy no-ops)

These are currently no-ops (the old `printLog` just filters and prints to stdout). Replace them with proper typed events.

### Step 5.1: Migrate `canopy-terminal/src/Make.hs` (5 calls)

- `setLogFlag` calls → delete entirely (config is env-var driven now)
- `printLog` calls → replace with `Log.logEvent (BuildLogLegacy msg)` or proper typed events

### Step 5.2: Migrate `canopy-terminal/src/Check.hs` (1 call)

- `setLogFlag` → delete

### Step 5.3: Migrate `canopy-terminal/src/Publish.hs` (1 call)

- `printLog` → proper typed event or delete if no longer useful

### Step 5.4: Migrate `canopy-terminal/src/Make/Environment.hs` (1 call)

- `setLogFlag` → delete

### Step 5.5: Migrate `canopy-terminal/src/Make/Generation.hs` (4 calls)

- `printLog` calls → typed events

### Step 5.6: Migrate `canopy-terminal/src/Make/Output.hs` (7 calls)

- `printLog` calls → typed events

### Step 5.7: Migrate `canopy-core/src/File/Package.hs` (7 calls)

- `Logger.printLog` calls → typed events for package operations:
```haskell
  | PackageDownloadStarted  !Text     -- package name
  | PackageDownloadCompleted !Text !Int -- name, bytes
  | PackageCacheHit         !Text
```

### Step 5.8: Migrate `canopy-core/src/File/Archive.hs` (21 calls)

- `Logger.printLog` calls → typed events for archive operations:
```haskell
  | ArchiveExtractStarted  !FilePath
  | ArchiveExtractCompleted !FilePath !Int  -- path, file count
  | ArchiveEntryProcessed  !FilePath
```

### Validation checkpoint

```bash
make build && make test
```

---

## Phase 6: Delete Legacy Systems

### Step 6.1: Delete `Logging.Debug`

- **Delete**: `packages/canopy-core/src/Logging/Debug.hs` (332 lines)
- **Remove** from `canopy-core.cabal` exposed-modules
- Verify no remaining imports: `grep -r "Logging.Debug" packages/`

### Step 6.2: Delete `Debug.Logger`

- **Delete**: `packages/canopy-query/src/Debug/Logger.hs` (~120 lines)
- **Remove** from `canopy-query.cabal` exposed-modules
- Verify no remaining imports: `grep -r "Debug.Logger" packages/`

### Step 6.3: Remove `*LogLegacy` constructors from `LogEvent`

After all call sites are migrated, the legacy constructors are unused. Remove:
```haskell
  | ParseLogLegacy     !String
  | TypeLogLegacy      !String
  | CanonLogLegacy     !String
  | CompileLogLegacy   !String
  | CacheLogLegacy     !String
  | QueryLogLegacy     !String
  | WorkerLogLegacy    !String
  | KernelLogLegacy    !String
  | FFILogLegacy       !String
  | GenerateLogLegacy  !String
  | BuildLogLegacy     !String
  | PermissionsLogLegacy !String
  | DepsSolverLogLegacy !String
```

Also remove the deprecated `printLog`/`setLogFlag` wrappers from `Logging.Logger`.

### Step 6.4: Clean up old/ references

Files in `old/` that import `Logging.Logger` or `Debug.Logger` — update their imports if they're still compiled, or leave them alone if they're truly dead code.

### Validation checkpoint

```bash
make build && make test
grep -r "Debug\.Logger\|Logging\.Debug\|Logging\.Logger" packages/ | grep -v "Logging/Logger.hs\|Logging/Event\|Logging/Config\|Logging/Sink\|Logging/Metrics"
# Should return nothing
```

---

## Phase 7: JSON Sink and ToJSON Instances

### Step 7.1: Add `ToJSON` instances in `Logging/Event.hs`

Implement `ToJSON` for:
- `LogEvent` — each constructor becomes a JSON object with `"event"` discriminator field
- `LogLevel` — lowercase string
- `Phase` — lowercase string
- All stats records
- `Duration` — integer microseconds

### Step 7.2: Implement JSON sink in `Logging/Sink.hs`

The `jsonSink` function:
- Encodes each event as a JSON object
- Adds `"ts"` (ISO 8601 timestamp) and `"level"` fields
- Writes one object per line (NDJSON format)
- Output to configured handle (stderr or file)

### Step 7.3: Wire `CANOPY_LOG_FORMAT=json` in Config

Config parsing already designed for this. Wire the `jsonSink` into the sink list when format is JSON.

### Validation checkpoint

```bash
make build && make test
CANOPY_LOG=INFO CANOPY_LOG_FORMAT=json canopy make 2>/tmp/events.ndjson
# Verify valid JSON per line:
cat /tmp/events.ndjson | python3 -c "import sys,json; [json.loads(l) for l in sys.stdin]"
```

---

## Phase 8: Tests

### Step 8.1: Unit tests for `Logging/Config.hs`

- Config parsing from env var strings
- Level filtering logic
- Phase filtering logic
- `CANOPY_DEBUG` backward compatibility
- Edge cases: empty string, invalid level, unknown phase names

### Step 8.2: Unit tests for `Logging/Event.hs`

- `eventLevel` returns correct level for every constructor
- `eventPhase` returns correct phase for every constructor
- `renderEventCLI` produces non-empty string for every constructor

### Step 8.3: Unit tests for `Logging/Sink.hs`

- CLI sink formats correctly
- JSON sink produces valid JSON for every event constructor
- `nullSink` produces no output
- `combineSinks` dispatches to all sinks

### Step 8.4: Integration test

- Simulate a compile pipeline emitting events
- Verify events appear in correct order
- Verify filtering by level/phase works

### Step 8.5: Golden tests for JSON output

- Emit a fixed set of events through JSON sink
- Compare against golden `.json` files

---

## File Summary

### New files (5):

| File | Lines | Purpose |
|------|-------|---------|
| `canopy-core/src/Logging/Event.hs` | ~250 | LogEvent ADT, Phase, Duration, stats records, eventLevel, eventPhase |
| `canopy-core/src/Logging/Config.hs` | ~180 | Unified env var config, LogConfig, shouldEmit |
| `canopy-core/src/Logging/Sink.hs` | ~200 | CLI + JSON + File sinks, combineSinks |
| `canopy-core/src/Logging/Metrics.hs` | ~50 | timed, Duration utilities |
| `test/Unit/Logging/` | ~300 | Tests for Config, Event, Sink |

### Rewritten files (1):

| File | Purpose |
|------|---------|
| `canopy-core/src/Logging/Logger.hs` | New unified IO API (replaces 22-line no-op) |

### Deleted files (2):

| File | Lines | Reason |
|------|-------|--------|
| `canopy-core/src/Logging/Debug.hs` | 332 | Replaced by new system |
| `canopy-query/src/Debug/Logger.hs` | ~120 | Replaced by new system |

### Modified files (24):

All 24 files from the call site inventory get their logging imports and calls updated.

### Total estimated: ~1400 lines new, ~470 lines deleted, ~24 files modified

---

## Execution Order

```
Phase 1  (Foundation)        — New modules, backward compat, zero behavior change
  ↓
Phase 2  (Shim)              — Debug.Logger delegates to new system
  ↓                            BUILD + TEST checkpoint
Phase 3  (Driver migration)  — 146 calls across 11 files → typed events
  ↓                            BUILD + TEST checkpoint
Phase 4  (Builder migration) — 31 calls across 5 files → typed events
  ↓                            BUILD + TEST checkpoint
Phase 5  (Terminal migration)— 47 calls across 8 files → typed events
  ↓                            BUILD + TEST checkpoint
Phase 6  (Delete legacy)     — Remove 3 old modules, legacy constructors
  ↓                            BUILD + TEST checkpoint
Phase 7  (JSON output)       — ToJSON instances, JSON sink, format config
  ↓                            BUILD + TEST checkpoint
Phase 8  (Tests)             — Unit, integration, golden tests
  ↓                            FINAL BUILD + TEST
```

Each phase is independently shippable. After Phase 2, the system is unified even though call sites still use string messages. After Phase 6, all legacy code is gone. Phase 7-8 are polish.
