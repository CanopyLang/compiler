# Plan 19: REPL Incremental Compilation

**Priority:** MEDIUM
**Effort:** Large (3-5d)
**Risk:** High -- Requires understanding of the full Build pipeline and Details caching

## Problem

Every REPL input triggers a full recompilation cycle. Typing `1 + 1` recompiles the entire project including all dependencies. This makes the REPL unusable for projects with more than a few modules.

### Current Compilation Model

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Repl/Eval.hs`

Lines 117-133 -- `attemptEval` runs a full compilation on every input:
```haskell
attemptEval :: Env -> State -> State -> Output -> IO State
attemptEval (Env root interpreter ansi) oldState newState output =
  compileAndExecute >>= handleResult
  where
    compileAndExecute =
      BW.withScope (runCompilation root ansi newState output)
        >>= either (pure . Left) (fmap Right . maybeExecute)
```

Lines 279-291 -- `runCompilation` calls `Build.fromRepl` every time:
```haskell
runCompilation :: FilePath -> Bool -> State -> Output -> BW.Scope -> IO (Either Exit.Repl (Maybe Builder))
runCompilation rootDir enableAnsi _state output scope =
  Stuff.withRootLock rootDir (Task.run compilationTask)
  where
    compilationTask = do
      details <- Task.io (Details.load Reporting.silent scope rootDir)
        >>= either (Task.throw . Exit.ReplBadDetails) pure
      artifacts <- Task.io (Build.fromRepl rootDir details)
        >>= either (Task.throw . Exit.ReplCannotBuild) pure
      traverse (generateJavaScript ...) (toPrintName output)
```

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Build.hs` (lines 102-115)

`Build.fromRepl` compiles the entire project from scratch:
```haskell
fromRepl :: FilePath -> Details.Details -> IO (Either BuildExit.BuildError Artifacts)
fromRepl root details = do
  let pkg = case details ^. Details.detailsOutline of
        Details.ValidApp _ -> Details.dummyPkgName
        Details.ValidPkg pkgName _ _ -> pkgName
      isApp = ...
      srcDirs = details ^. Details.detailsSrcDirs
  Compiler.compileFromExposed pkg isApp (Compiler.ProjectRoot root)
    (fmap Compiler.AbsoluteSrcDir srcDirs)
    (NonEmptyList.List (Name.fromChars "Main") [])
```

### REPL State Model

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Repl/Eval.hs`

Lines 194-210 -- `writeReplSource` recreates the entire module file on each input:
```haskell
writeReplSource :: FilePath -> State -> String -> IO ()
writeReplSource rootDir (State imports types decls) exprStr =
  BS.writeFile sourcePath (LBS.toStrict (BB.toLazyByteString moduleBuilder))
  where
    sourcePath = rootDir </> "src" </> "Main.can"
    moduleBuilder =
      mconcat
        [ BB.stringUtf8 "module Main exposing (..)\n",
          Map.foldr mappend mempty imports,
          Map.foldr mappend mempty types,
          Map.foldr mappend mempty decls,
          Name.toBuilder Name.replValueToPrint,
          BB.stringUtf8 " =\n  ",
          BB.byteString (BSC.pack exprStr),
          BB.stringUtf8 "\n"
        ]
```

The REPL state (`State` from `Repl.Types`) holds:
- `imports :: Map Name Builder` -- accumulated import statements
- `types :: Map Name Builder` -- accumulated type declarations
- `decls :: Map Name Builder` -- accumulated value declarations

These are stored as raw `Builder` (ByteString builders), not as typed AST fragments. On each input, the whole module is regenerated as text, written to disk, then fully recompiled.

### What Gets Recompiled Unnecessarily

1. **Details loading** -- `Details.load` is called every time to read `canopy.json` and resolve packages
2. **Dependency compilation** -- All packages (elm/core, elm/html, etc.) are re-checked
3. **Source parsing** -- The entire `Main.can` is re-parsed including unchanged imports/declarations
4. **Canonicalization** -- Full name resolution including unchanged definitions
5. **Type checking** -- Full type inference of all declarations
6. **Optimization** -- Full optimization pass
7. **Code generation** -- Full JS generation

Only the last expression is new. Everything else is identical to the previous REPL iteration.

## Proposed Solution

### Phase 1: Cache Details and Dependency Interfaces

#### Step 1.1: Persist Details Across REPL Iterations

**File:** `/home/quinten/fh/canopy/packages/canopy-terminal/src/Repl/Eval.hs`

Add cached state to `Env`:
```haskell
-- Current:
data Env = Env
  { _envRoot :: FilePath
  , _envInterpreter :: FilePath
  , _envAnsi :: Bool
  }

-- Proposed:
data Env = Env
  { _envRoot :: FilePath
  , _envInterpreter :: FilePath
  , _envAnsi :: Bool
  , _envDetails :: IORef (Maybe Details.Details)
  , _envArtifacts :: IORef (Maybe Build.Artifacts)
  }
```

On first REPL input, load Details and cache it. On subsequent inputs, reuse the cached Details unless the user adds a new import that requires re-resolving.

#### Step 1.2: Cache Dependency Artifacts

The dependency interfaces (elm/core, elm/html, etc.) never change during a REPL session. Cache the `Artifacts` from `Build.fromRepl` and only recompile the user's `Main` module.

### Phase 2: Incremental Source Generation

#### Step 2.1: Track What Changed

Instead of regenerating the entire `Main.can` file, track which parts of the REPL state changed:

```haskell
data ReplDelta
  = DeltaNewImport Name Builder
  | DeltaNewType Name Builder
  | DeltaNewDecl Name Builder
  | DeltaNewExpr String
```

When only a new expression is evaluated (the common case), we can skip reparsing/rechecking all existing declarations.

#### Step 2.2: Compile Only the Delta

For expression evaluation (the most common REPL operation):
1. Reuse the previously compiled module's interface and canonical AST
2. Parse only the new expression
3. Canonicalize only the new expression against the existing module's scope
4. Type-check only the new expression
5. Generate JS only for the new binding

This requires the Driver to support partial compilation, which is a significant change.

### Phase 3: Use Query Engine Caching

The Driver (`/home/quinten/fh/canopy/packages/canopy-driver/src/Driver.hs`) already has a query engine with caching:

Lines 375-382:
```haskell
logCacheStats :: Engine.QueryEngine -> IO ()
logCacheStats engine = do
  cacheSize <- Engine.getCacheSize engine
  hits <- Engine.getCacheHits engine
  misses <- Engine.getCacheMisses engine
```

#### Step 3.1: Share Query Engine Across REPL Iterations

Create the `QueryEngine` once in `initEnv` and reuse it for all REPL compilations. The engine's content-hash-based caching will automatically skip re-executing queries whose inputs haven't changed.

```haskell
-- In initEnv:
engine <- Engine.initEngine
-- Store in Env, pass to all runCompilation calls
```

#### Step 3.2: Use compileModuleWithEngine

The Driver already has `compileModuleWithEngine` (line 89) that accepts a shared engine:
```haskell
compileModuleWithEngine ::
  Engine.QueryEngine ->
  Pkg.Name ->
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  Parse.ProjectType ->
  IO (Either QueryError CompileResult)
```

Replace the `Build.fromRepl` + `Compiler.compileFromExposed` chain with direct `compileModuleWithEngine` calls, using the persisted engine.

## Files to Modify

| File | Change | Lines |
|------|--------|-------|
| `packages/canopy-terminal/src/Repl/Types.hs` | Add cached state fields to Env | N/A |
| `packages/canopy-terminal/src/Repl/Eval.hs` | Cache Details/Artifacts, share QueryEngine | 117-291 |
| `packages/canopy-terminal/src/Build.hs` | Add `fromReplIncremental` that accepts cached artifacts | 102-115 |
| `packages/canopy-driver/src/Driver.hs` | Expose engine-sharing API for REPL use | 89-100 |

## Verification

```bash
# 1. All existing tests pass
make test

# 2. REPL still works correctly
# echo ':type 1 + 1' | canopy repl
# Should output: number

# 3. REPL performance measurement
# Time the second expression in a REPL session
# Before: ~2-5 seconds for simple expressions in real projects
# After: <500ms target for expression-only inputs

# 4. State accumulation still works
# x = 1
# y = x + 1
# y  -- should output 2

# 5. Import addition still works
# import String
# String.length "hello"  -- should output 5
```

## Implementation Priority

Phase 1 (cache Details + artifacts) provides the biggest win for the least effort:
- Details loading is ~100ms per invocation (file I/O + JSON parsing)
- Dependency compilation is ~500ms-2s depending on project size
- These are completely unchanged between REPL inputs

Phase 3 (shared query engine) is the next biggest win:
- The query engine's caching means that even if we recompile Main.can, unchanged query results (parse, canonicalize of stable declarations) are cached

Phase 2 (incremental source generation) is the most complex and can be deferred unless Phase 1+3 are insufficient.
