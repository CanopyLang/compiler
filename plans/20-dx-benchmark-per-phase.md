# Plan 20: Benchmark Per-Phase Timing

**Priority:** MEDIUM
**Effort:** Small (4-8h)
**Risk:** Low -- Additive instrumentation, no changes to compilation logic

## Problem

The benchmark tool (`Bench.hs`) claims to provide "per-phase breakdown (parse, canonicalize, type check, optimize, generate)" in its module documentation, but only measures end-to-end compilation time. There is no per-phase timing.

### Current Implementation

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Bench.hs`

Lines 5-16 -- Documentation claims per-phase breakdown:
```haskell
-- * End-to-end compilation timing
-- * Per-phase breakdown (parse, canonicalize, type check, optimize, generate)
-- * Multiple iteration support for statistical significance
-- * JSON output for CI integration
-- * Comparison with previous baseline
```

Lines 92-100 -- `runIteration` only measures total time:
```haskell
runIteration :: FilePath -> Flags -> Int -> IO BenchResult
runIteration root flags iter = do
  when (flags ^. benchVerbose) $ do
    let iterStr = show iter
    Print.println [c|  Iteration #{iterStr}...|]
  start <- Clock.getCurrentTime
  compileProject root
  end <- Clock.getCurrentTime
  pure (BenchResult (realToFrac (Clock.diffUTCTime end start)) iter)
```

Lines 57-62 -- `BenchResult` only stores total time:
```haskell
data BenchResult = BenchResult
  { _brTotal :: !Double,
    _brIteration :: !Int
  }
```

Lines 106-126 -- `compileProject` calls `Compiler.compileFromPaths` as a black box:
```haskell
compileProject :: FilePath -> IO ()
compileProject root = do
  detailsResult <- Details.load Reporting.silent () root
  case detailsResult of
    Left _ -> Print.printErrLn ...
    Right details -> compileWithDetails root details

compileWithDetails :: FilePath -> Details.Details -> IO ()
compileWithDetails root details = do
  ...
  result <- Compiler.compileFromPaths pkg True (Compiler.ProjectRoot root) srcDirs canFiles
  ...
```

No per-phase timing hooks exist in the compilation call.

### The Driver Already Has Phase Tracking

**File:** `/home/quinten/fh/canopy/packages/canopy-driver/src/Driver.hs`

Lines 216-227 -- Each phase is already separated with `Engine.trackPhaseExecution`:
```haskell
runParsePhase engine path projectType = do
  Engine.trackPhaseExecution engine "parse"
  ParseQuery.parseModuleQuery projectType path

runCanonicalizePhase engine path pkg projectType ifaces ffiContent sourceModule = do
  Engine.trackPhaseExecution engine "canonicalize"
  CanonQuery.canonicalizeModuleQuery ...

runTypeCheckPhase engine path canonModule = do
  Engine.trackPhaseExecution engine "typecheck"
  TypeQuery.typeCheckModuleQuery path canonModule

runOptimizePhase engine types canonModule = do
  Engine.trackPhaseExecution engine "optimize"
  OptQuery.optimizeModuleQuery types canonModule
```

However, `Engine.trackPhaseExecution` only logs events -- it does not measure and return durations. The log events use `Duration 0` placeholders:

Line 131: `Log.logEvent (CompileCompleted path (CompileStats 1 (Duration 0)))`

Lines 302: `Log.logEvent (CompileCompleted "<source>" (CompileStats 1 (Duration 0)))`

## Proposed Solution

### Phase 1: Add Timing to Driver Phase Functions

#### Step 1.1: Create Timed Phase Wrappers

**File:** `/home/quinten/fh/canopy/packages/canopy-driver/src/Driver.hs`

Add a timing utility and per-phase duration tracking:

```haskell
-- | Per-phase timing results for a single module compilation.
data PhaseTimings = PhaseTimings
  { _timeParse :: !Double
  , _timeCanonicalize :: !Double
  , _timeTypeCheck :: !Double
  , _timeOptimize :: !Double
  , _timeGenerate :: !Double
  } deriving (Eq, Show)

-- | Time a single IO action, returning (result, seconds).
timePhase :: IO a -> IO (a, Double)
timePhase action = do
  start <- Clock.getCurrentTime
  result <- action
  end <- Clock.getCurrentTime
  pure (result, realToFrac (Clock.diffUTCTime end start))
```

#### Step 1.2: Extend CompileResult with Timings

**File:** `/home/quinten/fh/canopy/packages/canopy-driver/src/Driver.hs` (line 63)

```haskell
-- Current:
data CompileResult = CompileResult
  { compileResultModule :: !Can.Module,
    compileResultTypes :: !(Map Name.Name Can.Annotation),
    compileResultInterface :: !Interface.Interface,
    compileResultLocalGraph :: !Opt.LocalGraph,
    compileResultFFIInfo :: !(Map String JS.FFIInfo)
  }

-- Proposed:
data CompileResult = CompileResult
  { compileResultModule :: !Can.Module,
    compileResultTypes :: !(Map Name.Name Can.Annotation),
    compileResultInterface :: !Interface.Interface,
    compileResultLocalGraph :: !Opt.LocalGraph,
    compileResultFFIInfo :: !(Map String JS.FFIInfo),
    compileResultTimings :: !PhaseTimings
  }
```

#### Step 1.3: Instrument compileModuleCore

**File:** `/home/quinten/fh/canopy/packages/canopy-driver/src/Driver.hs` (lines 173-214)

Wrap each phase call with `timePhase`:

```haskell
compileModuleCore engine pkg ifaces path projectType = do
  (parseResult, parseTime) <- timePhase (runParsePhase engine path projectType)
  case parseResult of
    Left err -> return (Left err)
    Right sourceModule -> do
      ffiContent <- loadFFIContent sourceModule
      (canonResult, canonTime) <- timePhase (runCanonicalizePhase engine path pkg projectType ifaces ffiContent sourceModule)
      case canonResult of
        Left err -> return (Left err)
        Right canonModule -> do
          (typeResult, typeTime) <- timePhase (runTypeCheckPhase engine path canonModule)
          case typeResult of
            Left err -> return (Left err)
            Right types -> do
              (optimizeResult, optTime) <- timePhase (runOptimizePhase engine types canonModule)
              case optimizeResult of
                Left err -> return (Left err)
                Right localGraph -> do
                  iface <- generateInterface pkg canonModule types
                  let timings = PhaseTimings parseTime canonTime typeTime optTime 0
                  return (Right (CompileResult canonModule types iface localGraph ffiInfoMap timings))
```

### Phase 2: Extend BenchResult with Per-Phase Data

#### Step 2.1: Add Phase Timing to BenchResult

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Bench.hs`

```haskell
-- Current:
data BenchResult = BenchResult
  { _brTotal :: !Double,
    _brIteration :: !Int
  }

-- Proposed:
data BenchResult = BenchResult
  { _brTotal :: !Double,
    _brIteration :: !Int,
    _brPhases :: !AggregatePhaseTimings
  }

-- Aggregate timings across all modules in one build
data AggregatePhaseTimings = AggregatePhaseTimings
  { _aggParse :: !Double
  , _aggCanonicalize :: !Double
  , _aggTypeCheck :: !Double
  , _aggOptimize :: !Double
  , _aggGenerate :: !Double
  } deriving (Eq, Show)
```

#### Step 2.2: Collect Timings from Compiler

Modify `compileProject` to use a `Driver.compileModuleWithEngine`-based pipeline that returns `CompileResult` with timings, or add a callback/accumulator pattern to `Compiler.compileFromPaths` that collects per-module timings.

### Phase 3: Display Per-Phase Results

#### Step 3.1: Terminal Output

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Bench.hs` (lines 167-191)

Add phase breakdown to `reportResultsTerminal`:

```haskell
reportResultsTerminal results = do
  ...existing stats...
  Print.newline
  Print.println [c|{bold|Phase Breakdown} (average):}|]
  Print.println [c|  Parse:         {cyan|#{parseStr}}|]
  Print.println [c|  Canonicalize:  {cyan|#{canonStr}}|]
  Print.println [c|  Type Check:    {cyan|#{typeStr}}|]
  Print.println [c|  Optimize:      {cyan|#{optStr}}|]
  Print.println [c|  Generate:      {cyan|#{genStr}}|]
```

#### Step 3.2: JSON Output

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Bench.hs` (lines 193-215)

Add phase data to `encodeResultsPayload`:

```haskell
encodeResultsPayload results =
  Encode.object
    [ "iterations" Encode.==> Encode.int (length results)
    , "average_ms" Encode.==> Encode.int (round (avg * 1000))
    , "phases_avg_ms" Encode.==> encodePhases avgPhases
    , "runs" Encode.==> Encode.list encodeRunWithPhases results
    ]

encodePhases :: AggregatePhaseTimings -> Encode.Value
encodePhases timings =
  Encode.object
    [ "parse_ms" Encode.==> Encode.int (round (_aggParse timings * 1000))
    , "canonicalize_ms" Encode.==> Encode.int (round (_aggCanonicalize timings * 1000))
    , "typecheck_ms" Encode.==> Encode.int (round (_aggTypeCheck timings * 1000))
    , "optimize_ms" Encode.==> Encode.int (round (_aggOptimize timings * 1000))
    , "generate_ms" Encode.==> Encode.int (round (_aggGenerate timings * 1000))
    ]
```

## Files to Modify

| File | Change | Lines |
|------|--------|-------|
| `packages/canopy-driver/src/Driver.hs` | Add `PhaseTimings`, `timePhase`; extend `CompileResult`; instrument `compileModuleCore` | 63-214 |
| `packages/canopy-terminal/src/Bench.hs` | Add `AggregatePhaseTimings`; extend `BenchResult`; update terminal and JSON output | 57-215 |
| `packages/canopy-terminal/src/Bench.hs` | Update `compileProject` to collect timings from compilation results | 106-126 |

## Verification

```bash
# 1. All tests pass
make test

# 2. Bench command still works
cd /path/to/sample/project && canopy bench

# 3. Phase breakdown appears in output
canopy bench 2>&1 | grep -c "Parse\|Canonicalize\|Type Check\|Optimize\|Generate"
# Should find 5 phase lines

# 4. JSON output has phase data
canopy bench --json 2>&1 | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert 'phases_avg_ms' in data, 'Missing phases_avg_ms'
phases = data['phases_avg_ms']
for key in ['parse_ms', 'canonicalize_ms', 'typecheck_ms', 'optimize_ms', 'generate_ms']:
    assert key in phases, f'Missing {key}'
print('JSON schema valid')
"

# 5. Phase times sum approximately to total
# (There will be some overhead from non-phase work like file I/O)
```

## Notes

The `Duration 0` placeholders in `CompileStats` (used by the logging system) should also be replaced with real timings as a side benefit of this work. The `Logging.Event` module defines `Duration` as a `Double` wrapper, so the timings can flow directly from `PhaseTimings` into log events.
