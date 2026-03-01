# Plan 10: Build/Parallel Silent Cycle Drop

**Priority:** HIGH
**Effort:** Small (3-5h)
**Risk:** Low -- adds error reporting to an existing silent-failure path

## Problem

`Build.Parallel.buildLevels` silently drops unprocessed modules when a cycle
prevents forward progress, returning an incomplete `CompilationPlan` with no
error or warning.  The caller has no indication that modules were silently
omitted.

### The Silent Drop

```haskell
-- /home/quinten/fh/canopy/packages/canopy-builder/src/Build/Parallel.hs:87-104
buildLevels ::
  Graph.DependencyGraph ->
  Set ModuleName.Raw ->
  Set ModuleName.Raw ->
  [[ModuleName.Raw]] ->
  [[ModuleName.Raw]]
buildLevels graph remaining processed levels =
  if Set.null remaining
    then levels
    else
      let nextLevel = Set.toList $ Set.filter (allDepsProcessed graph processed) remaining
       in if null nextLevel
            then levels -- No more progress possible (shouldn't happen with acyclic graph)
            else
              let processed' = Set.union processed (Set.fromList nextLevel)
                  remaining' = Set.difference remaining (Set.fromList nextLevel)
               in buildLevels graph remaining' processed' (nextLevel : levels)
```

Line 100: `if null nextLevel then levels` -- when no module in `remaining` has
all its dependencies in `processed`, `buildLevels` returns the levels built so
far, silently discarding all modules still in `remaining`.

The comment says "shouldn't happen with acyclic graph", but:

1. The graph is built from user-supplied module import lists. A cycle in user
   code (A imports B, B imports A) creates a cyclic graph that reaches this path.

2. While `Builder.Graph.hasCycle` and `Builder.Graph.topologicalSort` exist,
   they are not called before `groupByDependencyLevel`.  The only caller that
   checks for cycles is `Builder.hs:189`:

   ```haskell
   -- /home/quinten/fh/canopy/packages/canopy-builder/src/Builder.hs:187-189
   if Graph.hasCycle graph
     then do
       return (BuildFailure (BuildErrorCycle (Graph.getAllModules graph)))
   ```

   But `Compiler.Parallel.compileModulesInOrder` (lines 84-103) builds the
   graph and immediately calls `groupByDependencyLevel` without any cycle check:

   ```haskell
   -- /home/quinten/fh/canopy/packages/canopy-builder/src/Compiler/Parallel.hs:91-93
   let graph = buildDependencyGraph moduleInfo
   let plan = Parallel.groupByDependencyLevel graph
       levels = Parallel.planLevels plan
   ```

3. Even if cycles are theoretically prevented at a higher level, a defensive
   check here prevents silent data loss if the invariant is ever violated.

### Additional Unsafe Code

The `compileLevel` function (line 153-163) uses `error` for a missing module:

```haskell
-- /home/quinten/fh/canopy/packages/canopy-builder/src/Build/Parallel.hs:157-161
(\moduleName -> case Map.lookup moduleName statuses of
  Just status -> do
    result <- compileOne moduleName status
    return (moduleName, result)
  Nothing -> error $ "Module " ++ show moduleName ++ " not found in statuses map")
```

This is a partial function using `error` -- forbidden by the coding standards.

### Impact

1. **Silent module omission**: If a cycle exists, some modules are silently
   excluded from compilation. The compiler succeeds but produces incomplete
   output -- missing modules, missing generated code, broken runtime behavior.

2. **Crash on missing status**: If the statuses map is inconsistent with the
   graph, the compiler crashes with an unhelpful Haskell error.

## Files to Modify

### 1. `packages/canopy-builder/src/Build/Parallel.hs`

#### Add error type and change return types

**Add to module exports (lines 26-32):**

```haskell
    -- * Error Types
    ParallelBuildError (..),
```

**Add error type:**

```haskell
-- | Errors that can occur during parallel level building.
--
-- @since 0.19.2
data ParallelBuildError
  = CycleDetectedDuringLeveling ![ModuleName.Raw]
    -- ^ A dependency cycle was detected during level computation.
    -- Contains the modules that could not be assigned to any level.
  | ModuleMissingFromStatuses !ModuleName.Raw
    -- ^ A module in the dependency graph was not found in the
    -- compilation statuses map. Contains the missing module name.
  deriving (Eq, Show)
```

#### Change `groupByDependencyLevel` to report cycles

**Current (lines 59-67):**

```haskell
groupByDependencyLevel :: Graph.DependencyGraph -> CompilationPlan
groupByDependencyLevel graph =
  let modules = Graph.getAllModules graph
      levels = computeLevels graph modules
      totalCount = sum (map length levels)
   in CompilationPlan
        { planLevels = levels,
          planTotalModules = totalCount
        }
```

**Proposed:**

```haskell
groupByDependencyLevel :: Graph.DependencyGraph -> Either ParallelBuildError CompilationPlan
groupByDependencyLevel graph =
  let modules = Graph.getAllModules graph
      (levels, unprocessed) = computeLevels graph modules
      totalCount = sum (map length levels)
   in if Set.null unprocessed
        then Right CompilationPlan
          { planLevels = levels,
            planTotalModules = totalCount
          }
        else Left (CycleDetectedDuringLeveling (Set.toList unprocessed))
```

#### Change `computeLevels` to return unprocessed modules

**Current (lines 71-77):**

```haskell
computeLevels :: Graph.DependencyGraph -> [ModuleName.Raw] -> [[ModuleName.Raw]]
computeLevels graph allModules =
  let initialLevel = filter (hasNoDeps graph) allModules
      levels = buildLevels graph (Set.fromList allModules) (Set.fromList initialLevel) [initialLevel]
   in reverse levels
```

**Proposed:**

```haskell
computeLevels :: Graph.DependencyGraph -> [ModuleName.Raw] -> ([[ModuleName.Raw]], Set ModuleName.Raw)
computeLevels graph allModules =
  let initialLevel = filter (hasNoDeps graph) allModules
      allSet = Set.fromList allModules
      processedSet = Set.fromList initialLevel
      (levels, finalRemaining) = buildLevels graph allSet processedSet [initialLevel]
   in (reverse levels, finalRemaining)
```

#### Change `buildLevels` to return remaining modules

**Current (lines 87-104):**

```haskell
buildLevels ::
  Graph.DependencyGraph ->
  Set ModuleName.Raw ->
  Set ModuleName.Raw ->
  [[ModuleName.Raw]] ->
  [[ModuleName.Raw]]
buildLevels graph remaining processed levels =
  if Set.null remaining
    then levels
    else
      let nextLevel = Set.toList $ Set.filter (allDepsProcessed graph processed) remaining
       in if null nextLevel
            then levels
            else ...
```

**Proposed:**

```haskell
buildLevels ::
  Graph.DependencyGraph ->
  Set ModuleName.Raw ->
  Set ModuleName.Raw ->
  [[ModuleName.Raw]] ->
  ([[ModuleName.Raw]], Set ModuleName.Raw)
buildLevels graph remaining processed levels
  | Set.null remaining = (levels, Set.empty)
  | null nextLevel = (levels, remaining)
  | otherwise =
      buildLevels graph remaining' processed' (nextLevel : levels)
  where
    nextLevel = Set.toList (Set.filter (allDepsProcessed graph processed) remaining)
    processed' = Set.union processed (Set.fromList nextLevel)
    remaining' = Set.difference remaining (Set.fromList nextLevel)
```

#### Fix `compileLevel` to remove `error`

**Current (lines 153-163):**

```haskell
compileLevel compileOne statuses modules =
  do
    results <- Async.mapConcurrently
      (\moduleName -> case Map.lookup moduleName statuses of
        Just status -> do
          result <- compileOne moduleName status
          return (moduleName, result)
        Nothing -> error $ "Module " ++ show moduleName ++ " not found in statuses map")
      modules
    return $ Map.fromList results
```

**Proposed:**

```haskell
compileLevel ::
  (ModuleName.Raw -> status -> IO a) ->
  Map ModuleName.Raw status ->
  [ModuleName.Raw] ->
  IO (Either ParallelBuildError (Map ModuleName.Raw a))
compileLevel compileOne statuses modules = do
  let missingModules = filter (\m -> not (Map.member m statuses)) modules
  case missingModules of
    (m : _) -> return (Left (ModuleMissingFromStatuses m))
    [] -> do
      results <- Async.mapConcurrently (compileOneModule compileOne statuses) modules
      return (Right (Map.fromList results))

compileOneModule ::
  (ModuleName.Raw -> status -> IO a) ->
  Map ModuleName.Raw status ->
  ModuleName.Raw ->
  IO (ModuleName.Raw, a)
compileOneModule compileOne statuses moduleName =
  case Map.lookup moduleName statuses of
    Just status -> do
      result <- compileOne moduleName status
      return (moduleName, result)
    Nothing ->
      -- This case is guarded by the check in compileLevel, so this
      -- is truly unreachable. Using InternalError for defense-in-depth.
      InternalError.report
        "Build.Parallel.compileOneModule"
        ("Module not in statuses map: " <> Text.pack (show moduleName))
        "The pre-flight check in compileLevel should have caught this."
```

Alternatively, if we want to avoid `InternalError` entirely, we can restructure
`compileLevel` to build a `Map ModuleName.Raw status` subset first, guaranteeing
the lookup always succeeds.

#### Update `compileParallelWithGraph` return type

**Current (lines 121-134):**

```haskell
compileParallelWithGraph ::
  (ModuleName.Raw -> status -> IO a) ->
  Map ModuleName.Raw status ->
  Graph.DependencyGraph ->
  IO (Map ModuleName.Raw a)
```

**Proposed:**

```haskell
compileParallelWithGraph ::
  (ModuleName.Raw -> status -> IO a) ->
  Map ModuleName.Raw status ->
  Graph.DependencyGraph ->
  IO (Either ParallelBuildError (Map ModuleName.Raw a))
```

### 2. `packages/canopy-builder/src/Build/Parallel/Instrumented.hs`

Update to handle the new `Either` return type from `groupByDependencyLevel`.

### 3. `packages/canopy-builder/src/Compiler/Parallel.hs`

**Current usage (lines 91-93):**

```haskell
let graph = buildDependencyGraph moduleInfo
let plan = Parallel.groupByDependencyLevel graph
    levels = Parallel.planLevels plan
```

**Proposed:**

```haskell
let graph = buildDependencyGraph moduleInfo
case Parallel.groupByDependencyLevel graph of
  Left (Parallel.CycleDetectedDuringLeveling cycleModules) ->
    return (Left (Exit.BuildCannotCompile
      (Exit.CompileParseError ""
        ("Dependency cycle detected among modules: " ++ show cycleModules))))
  Right plan -> do
    let levels = Parallel.planLevels plan
    ...
```

Or better, add a `BuildCycleError` variant to `BuildError` if one does not
exist at the `Exit` level.  Check -- `Builder.hs` already has
`BuildErrorCycle ![ModuleName.Raw]` (line 99), but the `Exit.BuildError` type
in `Exit.hs` does not have an equivalent.  Map appropriately.

### 4. Callers in `Builder.hs`

The `Builder.hs` module uses `compileParallelWithGraph` indirectly. Verify it
still compiles and handles the new `Either`.

## Verification

### Unit Tests

Add cycle detection tests to `test/Unit/Builder/GraphTest.hs` or create a
new `test/Unit/Build/ParallelTest.hs`:

```haskell
testGroupByDependencyLevelDetectsCycle :: TestTree
testGroupByDependencyLevelDetectsCycle =
  testCase "groupByDependencyLevel returns Left for cyclic graph" $ do
    let deps =
          [ (mkName "A", [mkName "B"]),
            (mkName "B", [mkName "A"])
          ]
    let graph = Graph.buildGraph deps
    case Parallel.groupByDependencyLevel graph of
      Left (Parallel.CycleDetectedDuringLeveling modules) ->
        Set.fromList modules @?= Set.fromList [mkName "A", mkName "B"]
      Right _ ->
        assertFailure "Expected Left for cyclic graph"

testGroupByDependencyLevelAcyclic :: TestTree
testGroupByDependencyLevelAcyclic =
  testCase "groupByDependencyLevel returns Right for acyclic graph" $ do
    let deps =
          [ (mkName "Main", [mkName "Utils"]),
            (mkName "Utils", [mkName "Base"]),
            (mkName "Base", [])
          ]
    let graph = Graph.buildGraph deps
    case Parallel.groupByDependencyLevel graph of
      Left err -> assertFailure ("Unexpected error: " ++ show err)
      Right plan ->
        Parallel.planTotalModules plan @?= 3

testGroupByDependencyLevelPartialCycle :: TestTree
testGroupByDependencyLevelPartialCycle =
  testCase "groupByDependencyLevel detects partial cycle in larger graph" $ do
    let deps =
          [ (mkName "Main", [mkName "A"]),
            (mkName "A", [mkName "B"]),
            (mkName "B", [mkName "A"]),  -- cycle: A <-> B
            (mkName "Utils", [])         -- Utils is fine
          ]
    let graph = Graph.buildGraph deps
    case Parallel.groupByDependencyLevel graph of
      Left (Parallel.CycleDetectedDuringLeveling modules) -> do
        -- A, B, and Main (which depends on A) should all be stuck
        assertBool "A should be in unprocessed" (mkName "A" `elem` modules)
        assertBool "B should be in unprocessed" (mkName "B" `elem` modules)
      Right _ ->
        assertFailure "Expected Left for graph with partial cycle"
```

### Build Verification

```bash
# Build with warnings
stack build --ghc-options="-Wall -Werror" 2>&1

# Run parallel compilation tests
stack test --ta="--pattern Parallel"

# Run graph tests
stack test --ta="--pattern Graph"

# Full test suite
stack test
```

### Integration Test

Create a project with a circular import and verify the compiler reports the
cycle instead of silently omitting modules:

```bash
mkdir -p /tmp/canopy-cycle-test/src
echo 'module A exposing (..)\nimport B\na = 1' > /tmp/canopy-cycle-test/src/A.can
echo 'module B exposing (..)\nimport A\nb = 2' > /tmp/canopy-cycle-test/src/B.can

# Should report cycle error, not silently skip A and B
canopy make src/A.can 2>&1 | grep -i "cycle"
```

## Rollback Plan

Revert the `Build/Parallel.hs`, `Compiler/Parallel.hs`, and any `Exit.hs`
changes.  The functions revert to silently dropping cycles and using `error`
for missing statuses.  No data format changes.
