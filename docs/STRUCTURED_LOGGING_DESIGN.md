# Canopy Compiler: Structured Debug Logging Architecture

## 1. Audit Findings

### Current State

The Canopy compiler has **two independent, overlapping logging systems** and **zero logging in core compiler phases**.

#### System A: `Logging.Debug` (canopy-core)

| Aspect | Detail |
|--------|--------|
| Location | `packages/canopy-core/src/Logging/Debug.hs` |
| Env vars | `CANOPY_LOG`, `CANOPY_LOG_LEVEL` |
| Levels | TRACE, DEBUG, INFO, WARN, ERROR |
| Categories | 14 (PARSE, TYPE, CODEGEN, BUILD, COMPILE, DEPS_SOLVER, CACHE, QUERY, WORKER, KERNEL, FFI, PERMISSIONS, DRIVER, BOOTSTRAP) |
| Output | `putStrLn` with timestamp, level, category prefix |
| Config cache | `IORef` via `unsafePerformIO` (thread-safe reads) |
| Used by | Nobody in compiler core; only terminal/build tooling references it |

#### System B: `Debug.Logger` (canopy-query)

| Aspect | Detail |
|--------|--------|
| Location | `packages/canopy-query/src/Debug/Logger.hs` |
| Env var | `CANOPY_DEBUG` |
| Levels | None (single "debug" level) |
| Categories | 12 (overlapping but different names: `COMPILE_DEBUG`, `CACHE_DEBUG`, etc.) |
| Output | `putStrLn` with `[CATEGORY] message` format |
| Config cache | `unsafePerformIO` on a top-level `[DebugCategory]` |
| Used by | `Driver.hs`, `Queries.Parse.Module`, `Queries.Type.Check`, `Queries.Optimize` |

#### System C: `Logging.Logger` (canopy-core, disabled)

Legacy MVar-based logger. Disabled due to deadlocks. `printLog` and `setLogFlag` are no-ops.

### Critical Blind Spots

| Compiler Phase | Monad | Internal Logging |
|----------------|-------|-----------------|
| **Parse** (`Parse.Module.fromByteString`) | Pure `Either E.Error Src.Module` | **None** |
| **Canonicalize** (`Canonicalize.Module.canonicalize`) | `Result i [W.Warning] Can.Module` | **None** |
| **Type Constrain** (`Type.Constrain.Module.constrain`) | `IO Constraint` | **None** |
| **Type Solve** (`Type.Solve.run`) | `IO (Either (List Error) (Map Name Annotation))` | **None** |
| **Optimize** (`Optimize.Module.optimize`) | `Result i [W.Warning] Opt.LocalGraph` | **None** |
| **Generate** (`Generate.JavaScript.generate`) | Pure `Builder` | **None** |

The query wrappers in `canopy-driver` add surface-level logging (file sizes, declaration counts, success/failure), but the actual algorithms — parsing decisions, name resolution steps, constraint generation, unification, optimization passes — are completely opaque.

### Problems Summary

1. **Two systems, inconsistent naming**: `COMPILE` vs `COMPILE_DEBUG`, `CACHE` vs `CACHE_DEBUG`
2. **Stringly-typed**: All messages are `String` — no structured data, no machine-parseable output
3. **No phase context**: Cannot correlate a log message to the module, declaration, or expression being processed
4. **No timing**: No duration tracking for phases or sub-operations
5. **No log sinks**: Only `putStrLn` — no JSON, no file output, no filtering by output format
6. **No zero-cost in pure phases**: Parse and Optimize are pure — injecting `IO` logging breaks purity
7. **Stubs in wrappers**: `logConstraintInfo` is `_ -> debug TYPE "Constraints generated"`, `logWarning` is `"<warning>"`
8. **Dead code**: `Logging.Logger` is a no-op but still exported

---

## 2. Architecture Design

### Design Goals

1. **Type-safe**: Log events are an ADT, not strings
2. **Structured**: Events carry typed payloads extractable as JSON or pretty-printed CLI text
3. **Phase-scoped**: Every event knows which phase, module, and (optionally) declaration produced it
4. **Zero-cost when disabled**: Pure phases stay pure; logging adds no allocation when off
5. **Single system**: Replace both `Logging.Debug` and `Debug.Logger` with one unified module
6. **Composable sinks**: Write to stderr, files, or structured JSON independently
7. **Deterministic**: No observable side-effects in pure phases; timing only in IO wrapper

### Package Placement

```
packages/canopy-core/src/
  Logging/
    Event.hs          -- LogEvent ADT, LogLevel, Phase, Context
    Sink.hs           -- Sink typeclass + CLI/JSON/File implementations
    Config.hs         -- Environment-based configuration (replaces both systems)
    Logger.hs         -- Main API: log, logPhase, withContext (IO)
    Pure.hs           -- Pure logging accumulator for Result-based phases
    Metrics.hs        -- Timing, counters, phase duration tracking
```

### Module Dependency Graph

```
Config.hs  ──────────────────┐
    │                        │
    v                        v
Logger.hs (IO API)      Pure.hs (pure accumulator)
    │                        │
    ├───────────┬────────────┘
    v           v
 Event.hs   Sink.hs
    │           │
    v           v
 Metrics.hs  (aeson, bytestring)
```

### Core Design: Two Paths, One Event Type

The key insight is that Canopy's compiler phases use two fundamentally different effect systems:

- **IO phases** (Type.Constrain, Type.Solve, Driver): Can log directly via `IO`
- **Pure phases** (Parse, Canonicalize, Optimize): Use `Result` or `Either` — cannot do `IO`

The architecture provides **one `LogEvent` type** with **two accumulation strategies**:

```
IO phases    -->  Logger.log :: LogEvent -> IO ()     --> immediate sink dispatch
Pure phases  -->  Pure.log   :: LogEvent -> Result ... --> accumulated in warnings-style list,
                                                          flushed after phase completes in IO
```

---

## 3. LogEvent Type Design

```haskell
-- | Structured log event carrying typed payload.
--
-- Every log event captures: what happened, where it happened,
-- and severity. The payload is phase-specific and type-safe.
data LogEvent
  = -- Parse phase events
    ParseStarted      !FilePath !Int              -- ^ path, file size bytes
  | ParseCompleted    !FilePath !ParseStats        -- ^ path, declaration/import counts
  | ParseFailed       !FilePath !Text              -- ^ path, error summary

    -- Canonicalize phase events
  | CanonStarted      !ModuleName
  | CanonResolved     !ModuleName !Name !ResolveOutcome  -- ^ module, name, how it resolved
  | CanonCompleted    !ModuleName !CanonStats
  | CanonFailed       !ModuleName !Text

    -- Type checking events
  | TypeConstrainStarted   !ModuleName
  | TypeConstraintCreated  !ModuleName !ConstraintKind !Int  -- ^ module, kind, count
  | TypeSolveStarted       !ModuleName !Int                  -- ^ module, constraint count
  | TypeUnified            !ModuleName !Text !Text            -- ^ module, type1, type2
  | TypeSolveCompleted     !ModuleName !TypeStats
  | TypeSolveFailed        !ModuleName !Int                   -- ^ module, error count

    -- Optimize phase events
  | OptimizeStarted    !ModuleName
  | OptimizeInlined    !ModuleName !Name               -- ^ function was inlined
  | OptimizeDeadCode   !ModuleName !Int                -- ^ count of eliminated nodes
  | OptimizeCompleted  !ModuleName !OptStats
  | OptimizeFailed     !ModuleName !Text

    -- Code generation events
  | GenerateStarted   !ModuleName
  | GenerateEmitted   !ModuleName !Int                 -- ^ JS bytes emitted
  | GenerateCompleted !ModuleName !GenStats

    -- Build/Driver events
  | CompileStarted    !FilePath
  | CompilePhaseEnter !Phase !ModuleName
  | CompilePhaseExit  !Phase !ModuleName !Duration
  | CompileCompleted  !FilePath !CompileStats
  | CompileFailed     !FilePath !Phase !Text

    -- Cache events
  | CacheHit          !Phase !ModuleName
  | CacheMiss         !Phase !ModuleName
  | CacheEvict        !ModuleName !Text                -- ^ reason

    -- FFI events
  | FFILoading        !FilePath
  | FFILoaded         !FilePath !Int                   -- ^ bytes
  | FFIMissing        !FilePath

    -- Worker events
  | WorkerSpawned     !Int                             -- ^ worker ID
  | WorkerCompleted   !Int !Duration
  | WorkerFailed      !Int !Text
  deriving (Eq, Show)

-- | Phase identifier
data Phase
  = PhaseParse
  | PhaseCanon
  | PhaseTypeConstrain
  | PhaseTypeSolve
  | PhaseOptimize
  | PhaseGenerate
  deriving (Eq, Show, Ord)

-- | Resolve outcome for canonicalization
data ResolveOutcome
  = ResolvedLocal
  | ResolvedImport !ModuleName
  | ResolvedBuiltin
  | Ambiguous ![ModuleName]
  deriving (Eq, Show)

-- | Constraint kind for type phase logging
data ConstraintKind
  = CEqual
  | CLocal
  | CForeign
  | CPattern
  | CLet
  deriving (Eq, Show)

-- | Per-phase statistics records
data ParseStats = ParseStats
  { _parseStatDecls :: !Int
  , _parseStatImports :: !Int
  , _parseStatForeignImports :: !Int
  } deriving (Eq, Show)

data CanonStats = CanonStats
  { _canonStatResolved :: !Int
  , _canonStatWarnings :: !Int
  } deriving (Eq, Show)

data TypeStats = TypeStats
  { _typeStatBindings :: !Int
  , _typeStatConstraints :: !Int
  , _typeStatUnifications :: !Int
  } deriving (Eq, Show)

data OptStats = OptStats
  { _optStatNodes :: !Int
  , _optStatInlined :: !Int
  , _optStatDeadEliminated :: !Int
  } deriving (Eq, Show)

data GenStats = GenStats
  { _genStatBytes :: !Int
  , _genStatModules :: !Int
  } deriving (Eq, Show)

data CompileStats = CompileStats
  { _compileStatPhases :: !(Map Phase Duration)
  , _compileStatCacheHits :: !Int
  , _compileStatCacheMisses :: !Int
  } deriving (Eq, Show)

-- | Duration in microseconds
newtype Duration = Duration { _durationMicros :: Int }
  deriving (Eq, Show, Ord)
```

### LogLevel Assignment

Each event constructor has a fixed level:

```haskell
-- | Every event has a deterministic log level.
eventLevel :: LogEvent -> LogLevel
eventLevel = \case
  ParseStarted {}          -> DEBUG
  ParseCompleted {}        -> INFO
  ParseFailed {}           -> ERROR

  CanonStarted {}          -> DEBUG
  CanonResolved {}         -> TRACE  -- very high volume
  CanonCompleted {}        -> INFO
  CanonFailed {}           -> ERROR

  TypeConstrainStarted {}  -> DEBUG
  TypeConstraintCreated {} -> TRACE
  TypeSolveStarted {}      -> DEBUG
  TypeUnified {}           -> TRACE  -- very high volume
  TypeSolveCompleted {}    -> INFO
  TypeSolveFailed {}       -> ERROR

  OptimizeStarted {}       -> DEBUG
  OptimizeInlined {}       -> TRACE
  OptimizeDeadCode {}      -> DEBUG
  OptimizeCompleted {}     -> INFO
  OptimizeFailed {}        -> ERROR

  GenerateStarted {}       -> DEBUG
  GenerateEmitted {}       -> DEBUG
  GenerateCompleted {}     -> INFO

  CompileStarted {}        -> INFO
  CompilePhaseEnter {}     -> DEBUG
  CompilePhaseExit {}      -> DEBUG
  CompileCompleted {}      -> INFO
  CompileFailed {}         -> ERROR

  CacheHit {}              -> TRACE
  CacheMiss {}             -> DEBUG
  CacheEvict {}            -> DEBUG

  FFILoading {}            -> DEBUG
  FFILoaded {}             -> DEBUG
  FFIMissing {}            -> WARN

  WorkerSpawned {}         -> DEBUG
  WorkerCompleted {}       -> DEBUG
  WorkerFailed {}          -> ERROR
```

### Phase Extraction

```haskell
-- | Extract the phase from an event (for category filtering).
eventPhase :: LogEvent -> Phase
eventPhase = \case
  ParseStarted {}          -> PhaseParse
  ParseCompleted {}        -> PhaseParse
  ParseFailed {}           -> PhaseParse
  CanonStarted {}          -> PhaseCanon
  CanonResolved {}         -> PhaseCanon
  -- ... etc
  CacheHit phase _         -> phase
  CacheMiss phase _        -> phase
  -- Worker/Compile events map to their enclosing phase
  WorkerSpawned {}         -> PhaseParse  -- or context-dependent
  _                        -> PhaseParse  -- fallback
```

---

## 4. Logging Flow Diagram

```
                     ┌─────────────────────────────┐
                     │     Environment Variables     │
                     │  CANOPY_LOG=DEBUG:PARSE,TYPE  │
                     │  CANOPY_LOG_FORMAT=json       │
                     │  CANOPY_LOG_FILE=/tmp/log     │
                     └──────────────┬───────────────┘
                                    │
                                    v
                     ┌──────────────────────────────┐
                     │      Logging.Config           │
                     │  (parsed once, cached IORef)  │
                     │                               │
                     │  LogConfig                    │
                     │    configLevel    :: LogLevel  │
                     │    configPhases   :: [Phase]   │
                     │    configFormat   :: Format    │
                     │    configSinks    :: [Sink]    │
                     │    configEnabled  :: Bool      │
                     └──────────────┬───────────────┘
                                    │
                    ┌───────────────┴────────────────┐
                    │                                │
                    v                                v
     ┌──────────────────────┐         ┌──────────────────────────┐
     │   Pure Phases         │         │   IO Phases               │
     │  (Parse, Canon, Opt)  │         │  (Constrain, Solve, Gen) │
     │                       │         │                           │
     │  Pure.log :: LogEvent │         │  Logger.log :: LogEvent   │
     │    -> LogAccum        │         │    -> IO ()               │
     │                       │         │                           │
     │  Accumulates events   │         │  Checks config, if       │
     │  in [LogEvent] list   │         │  enabled, dispatches      │
     │  alongside warnings   │         │  to sinks immediately     │
     └──────────┬───────────┘         └──────────┬────────────────┘
                │                                 │
                │  (phase completes in IO)        │
                v                                 v
     ┌──────────────────────┐         ┌──────────────────────────┐
     │  Logger.flushEvents  │         │       Sink Dispatch       │
     │  :: [LogEvent]       │─────────│                           │
     │  -> IO ()            │         │  ┌─────────────────────┐  │
     └──────────────────────┘         │  │  Sink.CLI           │  │
                                      │  │  [DEBUG] [PARSE]    │  │
                                      │  │  Parse completed:   │  │
                                      │  │  12 decls, 5 imports│  │
                                      │  └─────────────────────┘  │
                                      │                           │
                                      │  ┌─────────────────────┐  │
                                      │  │  Sink.JSON           │  │
                                      │  │  {"event":"parse_   │  │
                                      │  │   completed",       │  │
                                      │  │   "decls":12, ...}  │  │
                                      │  └─────────────────────┘  │
                                      │                           │
                                      │  ┌─────────────────────┐  │
                                      │  │  Sink.File           │  │
                                      │  │  (append to logfile) │  │
                                      │  └─────────────────────┘  │
                                      └──────────────────────────┘
```

### Pure Phase Integration Detail

```
  Parse.Module.fromByteString
      │
      │ returns Either E.Error Src.Module
      │ (no logging capability — pure)
      │
      v
  Queries.Parse.Module.parseModuleQuery  (IO wrapper)
      │
      │ 1. Logger.log (ParseStarted path size)
      │ 2. call Parse.Module.fromByteString
      │ 3. case result of
      │      Left err  -> Logger.log (ParseFailed path (show err))
      │      Right mod -> Logger.log (ParseCompleted path stats)
      │
      v
  returns IO (Either QueryError Src.Module)
```

For phases using `Result` monad (Canon, Optimize), the pattern is similar — the IO query wrapper emits events before/after the pure computation. For deeper instrumentation inside pure code (e.g., logging each name resolution in Canon), we use the `Pure.log` accumulator:

```
  Canonicalize.Module.canonicalize
      │
      │ uses Result monad (pure, accumulates warnings)
      │
      │ Option A: Widen Result to carry [LogEvent] in info parameter
      │   Result [LogEvent] [Warning] Error Module
      │   Pure.log adds events via the info accumulator
      │
      │ Option B: Keep Result unchanged, log only at boundaries
      │   (simpler, less intrusive, recommended for Phase 1)
      │
      v
  Queries.Canonicalize.Module.canonicalizeModuleQuery  (IO wrapper)
      │ emits CanonStarted / CanonCompleted / CanonFailed
```

---

## 5. Implementation Plan

### Phase 1: Foundation (Logging.Event + Logging.Config + Logging.Sink)

**Goal**: Define the event type, configuration, and sink infrastructure. No behavioral changes yet.

**Steps**:

1. Create `Logging/Event.hs`:
   - Define `LogEvent` ADT with all constructors
   - Define `Phase`, `LogLevel`, stats records, `Duration`
   - Implement `eventLevel`, `eventPhase`
   - Full Haddock documentation

2. Create `Logging/Config.hs`:
   - Unified config parsing from `CANOPY_LOG`, `CANOPY_LOG_LEVEL`, `CANOPY_LOG_FORMAT`, `CANOPY_LOG_FILE`
   - `LogConfig` record with phase filtering, level threshold, format, sinks
   - Cached `IORef` via `unsafePerformIO` (same pattern as existing)
   - Replace both `CANOPY_LOG` and `CANOPY_DEBUG` with single system

3. Create `Logging/Sink.hs`:
   - `Sink` typeclass or record-of-functions
   - `cliSink`: Human-readable colored output to stderr (uses `Terminal.Print` + `ColorQQ`)
   - `jsonSink`: One JSON object per line to stderr or file
   - `fileSink`: Append to log file path
   - `nullSink`: Zero-cost discard

4. Add to `canopy-core.cabal`: new modules, `aeson` dependency for JSON sink

**Validation**: Modules compile, unit tests for config parsing and event rendering.

### Phase 2: IO Logger API (Logging.Logger)

**Goal**: Single unified logging API for IO phases.

**Steps**:

1. Create `Logging/Logger.hs`:
   - `log :: LogEvent -> IO ()` — checks config, dispatches to enabled sinks
   - `logWhen :: Bool -> LogEvent -> IO ()` — conditional logging
   - `withPhase :: Phase -> ModuleName -> IO a -> IO (a, Duration)` — timed phase wrapper
   - `flushEvents :: [LogEvent] -> IO ()` — batch dispatch for pure-phase accumulated events

2. Implement zero-cost guard:
   ```haskell
   log :: LogEvent -> IO ()
   log event = do
     cfg <- readConfig
     when (shouldEmit cfg event) (dispatch cfg event)
   ```

3. Add `Logging/Metrics.hs`:
   - `timed :: IO a -> IO (a, Duration)` — wall-clock timing
   - Phase duration tracking via `IORef (Map Phase [Duration])`
   - Summary statistics: `getMetricsSummary :: IO MetricsSummary`

**Validation**: Property tests for config filtering. Integration test logging a fake compile pipeline.

### Phase 3: Replace Debug.Logger in Driver

**Goal**: Migrate `canopy-driver` from `Debug.Logger` to `Logging.Logger` with typed events.

**Steps**:

1. Update `Driver.hs`:
   - Replace all `Logger.debug COMPILE_DEBUG ("...")` with `Log.log (CompileStarted path)` etc.
   - Use `Log.withPhase` around `runParsePhase`, `runCanonicalizePhase`, etc.
   - Remove `import Debug.Logger`

2. Update `Queries.Parse.Module`:
   - Replace `Logger.debug PARSE ("Starting parse query for: " ++ path)` with `Log.log (ParseStarted path fileSize)`
   - Replace success/failure logging with `ParseCompleted`/`ParseFailed`

3. Update `Queries.Type.Check`:
   - Replace string logging with `TypeConstrainStarted`, `TypeSolveStarted`, `TypeSolveCompleted`/`TypeSolveFailed`
   - Remove stub `logConstraintInfo`

4. Update `Queries.Optimize`:
   - Replace with `OptimizeStarted`, `OptimizeCompleted`/`OptimizeFailed`
   - Remove `logWarning` stub that prints `"<warning>"`

5. Update `logCacheStats` to use `CacheHit`/`CacheMiss` events

**Validation**: `make build` zero warnings. Existing tests pass. `CANOPY_LOG=DEBUG` produces typed output.

### Phase 4: Replace Logging.Debug in Terminal

**Goal**: Migrate any `Logging.Debug` users in terminal package to new system.

**Steps**:

1. Audit all imports of `Logging.Debug` across `canopy-terminal`
2. Replace with `Logging.Logger` calls using appropriate `LogEvent` constructors
3. For build-system events, add `BuildEvent` constructors if needed

**Validation**: `make build && make test` clean.

### Phase 5: Delete Legacy Systems

**Goal**: Remove dead code.

**Steps**:

1. Delete `packages/canopy-query/src/Debug/Logger.hs`
2. Delete `packages/canopy-core/src/Logging/Logger.hs` (disabled legacy)
3. Merge `Logging.Debug`'s env-var parsing logic into `Logging.Config` (already done in Phase 1)
4. Delete `packages/canopy-core/src/Logging/Debug.hs`
5. Remove from `.cabal` files
6. Update any re-exports

**Validation**: `make build && make test` clean. `grep -r "Debug.Logger\|Logging.Debug\|Logging.Logger" packages/` returns nothing.

### Phase 6: Deep Instrumentation (Optional, Per-Phase)

**Goal**: Add TRACE-level logging inside compiler core algorithms for debugging complex issues.

**Sub-phases** (each independent, can be done in any order):

6a. **Type Solver instrumentation**:
   - Log unification steps (`TypeUnified` events) inside `Type.Solve`
   - Log constraint traversal decisions
   - Since Solve runs in IO, use `Logger.log` directly
   - Gate behind `TRACE` level so zero cost at `DEBUG`/`INFO`

6b. **Canonicalization instrumentation**:
   - Widen `Result` info parameter to carry `[LogEvent]`
   - Log name resolution outcomes (`CanonResolved`)
   - Flush accumulated events in the query wrapper

6c. **Optimization instrumentation**:
   - Same `Result` widening approach
   - Log inlining decisions, dead code elimination counts

6d. **Parser instrumentation** (lowest priority):
   - Parser is pure `Either` — instrumentation requires changing return type
   - Recommend: keep parser logging at boundary only (Phase 3 already covers this)

**Validation**: Each sub-phase validated independently with `make build && make test`.

### Phase 7: JSON Output and Tooling

**Goal**: Machine-readable structured output for IDE integration and analysis.

**Steps**:

1. Implement `ToJSON` instances for all `LogEvent` constructors
2. JSON sink writes NDJSON (newline-delimited JSON) to file or stderr
3. Add `CANOPY_LOG_FORMAT=json` support in `Config.hs`
4. Document JSON schema for downstream tooling

**Validation**: Golden tests comparing JSON output against expected NDJSON files.

---

## 6. Example Logs

### CLI Output (`CANOPY_LOG=DEBUG`)

```
[2026-02-24 14:32:01] [INFO]  [parse]     Compile started: src/Main.elm
[2026-02-24 14:32:01] [DEBUG] [parse]     Parse started: src/Main.elm (2,847 bytes)
[2026-02-24 14:32:01] [INFO]  [parse]     Parse completed: src/Main.elm (12 decls, 5 imports, 0 FFI)
[2026-02-24 14:32:01] [DEBUG] [canon]     Canonicalize started: Main
[2026-02-24 14:32:01] [INFO]  [canon]     Canonicalize completed: Main (47 resolved, 0 warnings)
[2026-02-24 14:32:01] [DEBUG] [type]      Type constrain started: Main
[2026-02-24 14:32:01] [DEBUG] [type]      Type solve started: Main (83 constraints)
[2026-02-24 14:32:02] [INFO]  [type]      Type solve completed: Main (12 bindings, 83 constraints, 156 unifications)
[2026-02-24 14:32:02] [DEBUG] [optimize]  Optimize started: Main
[2026-02-24 14:32:02] [INFO]  [optimize]  Optimize completed: Main (45 nodes, 3 inlined, 7 dead-eliminated)
[2026-02-24 14:32:02] [DEBUG] [generate]  Generate started: Main
[2026-02-24 14:32:02] [INFO]  [generate]  Generate completed: Main (4,521 bytes)
[2026-02-24 14:32:02] [INFO]  [compile]   Compile completed: src/Main.elm
                                            parse: 12ms | canon: 8ms | type: 45ms | opt: 15ms | gen: 6ms
                                            cache: 3 hits, 1 miss
```

### CLI Output (`CANOPY_LOG=TRACE:TYPE`)

```
[2026-02-24 14:32:01] [DEBUG] [type]      Type constrain started: Main
[2026-02-24 14:32:01] [TRACE] [type]      Constraint created: CEqual (23 total)
[2026-02-24 14:32:01] [TRACE] [type]      Constraint created: CLet (4 total)
[2026-02-24 14:32:01] [DEBUG] [type]      Type solve started: Main (27 constraints)
[2026-02-24 14:32:01] [TRACE] [type]      Unified: Int ~ Int
[2026-02-24 14:32:01] [TRACE] [type]      Unified: String ~ String
[2026-02-24 14:32:01] [TRACE] [type]      Unified: (Int -> String) ~ (a -> b)
[2026-02-24 14:32:02] [INFO]  [type]      Type solve completed: Main (12 bindings, 27 constraints, 156 unifications)
```

### JSON Output (`CANOPY_LOG=INFO CANOPY_LOG_FORMAT=json`)

```json
{"ts":"2026-02-24T14:32:01.123Z","level":"info","phase":"parse","event":"compile_started","path":"src/Main.elm"}
{"ts":"2026-02-24T14:32:01.135Z","level":"info","phase":"parse","event":"parse_completed","path":"src/Main.elm","decls":12,"imports":5,"ffi_imports":0}
{"ts":"2026-02-24T14:32:01.143Z","level":"info","phase":"canon","event":"canon_completed","module":"Main","resolved":47,"warnings":0}
{"ts":"2026-02-24T14:32:02.188Z","level":"info","phase":"type","event":"type_solve_completed","module":"Main","bindings":12,"constraints":83,"unifications":156}
{"ts":"2026-02-24T14:32:02.203Z","level":"info","phase":"optimize","event":"optimize_completed","module":"Main","nodes":45,"inlined":3,"dead_eliminated":7}
{"ts":"2026-02-24T14:32:02.209Z","level":"info","phase":"generate","event":"generate_completed","module":"Main","bytes":4521}
{"ts":"2026-02-24T14:32:02.210Z","level":"info","phase":"compile","event":"compile_completed","path":"src/Main.elm","phases":{"parse_ms":12,"canon_ms":8,"type_ms":45,"opt_ms":15,"gen_ms":6},"cache_hits":3,"cache_misses":1}
```

---

## 7. DX Evaluation

### Developer Experience: Before vs After

| Scenario | Before | After |
|----------|--------|-------|
| "Why is my module slow to compile?" | No visibility. Must add `Debug.trace` manually, recompile. | `CANOPY_LOG=DEBUG` shows per-phase timing. `CANOPY_LOG=TRACE:TYPE` reveals unification bottlenecks. |
| "Is the cache working?" | `Debug.Logger` prints cache size. No hit/miss per-module. | `CacheHit`/`CacheMiss` events per module per phase. Summary in `CompileCompleted`. |
| "Type error is wrong — what happened?" | Completely opaque. Type solver has zero logging. | `CANOPY_LOG=TRACE:TYPE` shows every unification step leading to the error. |
| "CI build is flaky" | No structured output to parse. | `CANOPY_LOG_FORMAT=json` piped to analysis tools. Filter by `level:error`. |
| "IDE wants compilation progress" | No machine-readable events. | JSON sink provides real-time NDJSON stream with phase enter/exit events. |

### Configuration UX

```bash
# Quick overview
CANOPY_LOG=1 canopy make

# Debug specific phase
CANOPY_LOG=DEBUG:TYPE canopy make

# Full trace to file
CANOPY_LOG=TRACE CANOPY_LOG_FILE=/tmp/canopy.log canopy make

# JSON for tooling
CANOPY_LOG=INFO CANOPY_LOG_FORMAT=json canopy make 2>/tmp/events.ndjson

# Multiple phases
CANOPY_LOG=DEBUG:PARSE,TYPE,OPTIMIZE canopy make
```

---

## 8. Trade-offs and Risks

### Trade-offs

| Decision | Pro | Con | Mitigation |
|----------|-----|-----|------------|
| **ADT over strings** | Type-safe, refactorable, machine-parseable | More code to maintain; adding events requires ADT change | Events are append-only; rarely need modification |
| **Pure phases log at boundary only (Phase 1-5)** | No purity breakage, minimal intrusion | Cannot see inside algorithms | Phase 6 adds deep instrumentation incrementally |
| **Single config system replacing two** | One mental model, one env var | Migration required | Phase 3-5 are mechanical replacements |
| **`unsafePerformIO` for config** | Zero-cost when disabled, no threading of config | Impure at module level | Same pattern used by GHC, well-understood |
| **JSON via aeson** | Standard, well-tested | New dependency | `aeson` is already transitively depended on by many packages |
| **Timestamps in IO only** | Deterministic pure phases | Pure phase events have no timestamp | Timestamp added when flushed in IO wrapper |

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Performance regression from TRACE logging** | Medium | High (if always-on) | Zero-cost guard: config check before any allocation. TRACE-level events gated behind `shouldEmit` which short-circuits on cached IORef. |
| **Widening Result monad breaks API** | Low | Medium | Phase 6b/6c are optional. Boundary logging (Phase 3) covers 90% of use cases without touching Result. |
| **aeson dependency bloat** | Low | Low | JSON sink can be optional (behind cabal flag). CLI sink has zero extra deps. |
| **Log output interleaving in parallel compilation** | Medium | Low (cosmetic) | Each event is a single `hPutStrLn` call (atomic on most platforms). JSON sink is line-oriented. For strict ordering, use file sink with buffering. |
| **Migration breaks existing CANOPY_DEBUG users** | Medium | Low | Keep `CANOPY_DEBUG` as alias for `CANOPY_LOG` during transition. Emit deprecation warning. |

### What This Design Does NOT Do

- **No distributed tracing**: No span IDs or trace correlation across processes. Not needed for a single-process compiler.
- **No log rotation**: File sink is append-only. Use external tools (`logrotate`) if needed.
- **No runtime reconfiguration**: Config is read once at startup. Changing requires restart. This is intentional for zero-cost guarantees.
- **No sampling**: All events at enabled levels are emitted. Compiler runs are short enough that sampling is unnecessary.

---

## Summary

| Deliverable | Status |
|-------------|--------|
| Audit Findings | Complete — two overlapping systems, zero core phase logging |
| Architecture Design | Complete — dual-path (IO + pure accumulator), single event type |
| LogEvent Type Design | Complete — 30+ constructors covering all phases |
| Logging Flow Diagram | Complete — config → guard → sink dispatch |
| Implementation Plan | Complete — 7 phases, incremental, each independently validated |
| Example Logs | Complete — CLI (DEBUG + TRACE) and JSON formats |
| DX Evaluation | Complete — before/after comparison, config UX |
| Trade-offs & Risks | Complete — 6 trade-offs, 5 risks with mitigations |
