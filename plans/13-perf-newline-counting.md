# Plan 13: Newline Counting Double Materialization

**Priority:** MEDIUM
**Effort:** Small (4-6 hours)
**Risk:** Low (internal refactor, no output changes)

## Problem

The source map system counts newlines by materializing Builders to strict ByteStrings
solely for the purpose of counting `0x0A` bytes. This means every JS statement is
materialized twice: once for counting and once for final output.

### Current Data Flow

Every call to `addBuilder` or `addKernelChunks` materializes the Builder to count
newlines, then throws away the materialized bytes and keeps the Builder for later
final output:

```
Builder (from JS.stmtToBuilder)
  -> countNewlines: BL.toStrict (BB.toLazyByteString builder)  -- materializes to ByteString
  -> BS.count 0x0A                                              -- counts newlines
  -> ByteString is DISCARDED
  -> Builder stored in revBuilders                               -- materialized AGAIN at final output
```

### Affected Code

**`/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript.hs`:**

Lines 415: `addKernelChunks` materializes for dedup AND counting:
```haskell
addKernelChunks mode currentGlobal (State revKernels revBuilders seen seenChunks outLine smMappings srcLocs) chunks =
  let kernelCode = Kernel_.generateKernel mode chunks
      kernelBytes = BL.toStrict (BB.toLazyByteString kernelCode)
  in if Set.member kernelBytes seenChunks
     then State revKernels revBuilders (Set.insert currentGlobal seen) seenChunks outLine smMappings srcLocs
     else State (kernelCode : revKernels) revBuilders (Set.insert currentGlobal seen) (Set.insert kernelBytes seenChunks) (outLine + countNewlinesBS kernelBytes) smMappings srcLocs
```

Note: `addKernelChunks` is not wasteful -- it materializes for dedup (Set membership)
and reuses the bytes for counting. This is already optimal.

Lines 417-423: `addStmt`/`addBuilder` materializes ONLY for counting:
```haskell
addStmt :: State -> JS.Stmt -> State
addStmt state stmt =
  addBuilder state (JS.stmtToBuilder stmt)

addBuilder :: State -> Builder -> State
addBuilder (State revKernels revBuilders seen seenChunks outLine smMappings srcLocs) builder =
  State revKernels (builder : revBuilders) seen seenChunks (outLine + countNewlines builder) smMappings srcLocs
```

Lines 429-431: `countNewlines` materializes the Builder:
```haskell
countNewlines :: Builder -> Int
countNewlines b =
  countNewlinesBS (BL.toStrict (BB.toLazyByteString b))
```

Lines 437-439: `countNewlinesBS` scans the bytes:
```haskell
countNewlinesBS :: ByteString -> Int
countNewlinesBS =
  BS.count 0x0A
```

### Scale of the Problem

For a 200-module project:
- ~10,000 JS statements pass through `addStmt`/`addBuilder`
- Each statement's Builder is materialized to ByteString just for counting newlines
- The ByteString is immediately discarded
- The Builder is materialized again when `stateToBuilder` assembles final output
- This doubles the allocation for every statement in the codegen phase

### Source Map Context

The `_outputLine` field in `State` tracks the current line number in the generated
JavaScript. This is used by `emitMapping` (line 442-446) to create source map
mappings that record which generated JS line corresponds to which source AST node.

The source map feature is only used in Dev mode (`buildSourceMap` at line 462-468
returns `Nothing` for Prod mode), but newlines are counted unconditionally.

## Solution

### Approach A: Count Newlines at Final Materialization (Recommended)

Instead of counting newlines per-statement, count them once when the final output is
assembled. Change the source map to record Builder boundaries and compute line numbers
in a single pass over the final ByteString.

```haskell
-- Replace _outputLine with a list of (Builder, Maybe Opt.Global) pairs
-- that records which globals appear at which Builder boundary
data State = State
  { _revKernels :: [Builder]
  , _revBuilders :: [(Builder, Maybe Opt.Global)]  -- Builder + optional global for mapping
  , _seenGlobals :: Set Opt.Global
  , _seenKernelChunks :: Set ByteString
  , _pendingMappings :: [(Opt.Global, Int)]  -- global -> builder index
  , _sourceLocations :: Map Opt.Global Ann.Region
  }

-- Final assembly: materialize once, count newlines, build source map
finalizeState :: State -> (Builder, [SourceMap.Mapping])
finalizeState state =
  let pairs = reverse (_revBuilders state)
      -- Single pass: accumulate builders and count newlines
      (finalBuilder, mappings) = foldl' accumulate (mempty, []) pairs
  in (prependKernels (_revKernels state) finalBuilder, mappings)
```

### Approach B: Skip Counting in Prod Mode (Quick Win)

Since source maps are only generated in Dev mode, skip newline counting entirely
in Prod mode:

```haskell
addBuilder :: Mode.Mode -> State -> Builder -> State
addBuilder mode (State revKernels revBuilders seen seenChunks outLine smMappings srcLocs) builder =
  let newLine = case mode of
        Mode.Prod {} -> outLine  -- Skip counting in prod
        Mode.Dev {} -> outLine + countNewlines builder
  in State revKernels (builder : revBuilders) seen seenChunks newLine smMappings srcLocs
```

This requires threading `Mode` through `addBuilder` and `addStmt`, which already
receive it indirectly through their callers.

### Approach C: Count During Rendering (Zero Extra Allocation)

Modify `stmtToBuilder`/`exprToBuilder` to return `(Builder, Int)` where the `Int`
is the newline count, computed during AST-to-Builder conversion without extra
materialization:

```haskell
-- In Builder.hs, add counting variants
stmtToBuilderCounted :: Stmt -> (Builder, Int)
stmtToBuilderCounted stmt =
  let bs = LBS.toStrict (BB.toLazyByteString (renderJS (JSAstStatement (stmtToJS stmt) noAnnot)))
      count = BS.count 0x0A bs
  in (BB.byteString bs <> BB.char7 '\n', count + 1)
```

This still materializes, but the materialized bytes become the Builder itself
(via `BB.byteString`), so there is no double materialization. The trade-off is
that `BB.byteString` holds a reference to the strict ByteString instead of the
lazy Builder tree, which may increase peak memory but eliminates double work.

### Recommended: Combine B + C

1. Skip counting in Prod mode (Approach B) -- quick win, no risk
2. Use counted rendering (Approach C) for Dev mode -- eliminates double materialization

## Files to Modify

| File | Change |
|------|--------|
| `packages/canopy-core/src/Generate/JavaScript.hs` | Thread mode through `addBuilder`/`addStmt`; skip counting in Prod; use counted rendering in Dev |
| `packages/canopy-core/src/Generate/JavaScript/Builder.hs` | Add `stmtToBuilderCounted :: Stmt -> (Builder, Int)` variant |

## Verification

```bash
# Run golden tests to verify output unchanged
stack test --ta="--pattern JsGen"

# Run source map property tests
stack test --ta="--pattern SourceMap"

# Profile allocation improvement
stack exec -- canopy make +RTS -s -RTS  # compare before/after
stack bench --ba="--match prefix Bench.Generate"
```

## Expected Impact

- **Prod mode**: Eliminates all newline counting allocation (~50% of codegen allocation for source map tracking)
- **Dev mode**: Eliminates double materialization, reducing codegen allocation by ~30%
- Combined: 30-50% reduction in codegen phase allocation for typical projects
- Wall-clock improvement of 5-10% in codegen phase
