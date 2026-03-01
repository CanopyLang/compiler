# Plan 09: Discovery Parse Failure Graceful Degradation

**Priority:** HIGH
**Effort:** Small (4-6h)
**Risk:** Medium -- changes error propagation in the build pipeline, requires
careful testing that callers handle the new `Either` properly

## Problem

`Compiler.Discovery.parseModuleFile` and `Compiler.Discovery.parseModuleAtPath`
call `InternalError.report` when parsing fails, which terminates the entire
compiler process with `error`.  A single syntax error in any transitively
imported file crashes the compiler instead of producing a user-friendly parse
error.

### Crash Sites

**Site 1: `parseModuleFile`** (lines 83-90)

```haskell
-- /home/quinten/fh/canopy/packages/canopy-builder/src/Compiler/Discovery.hs:82-90
parseModuleFile :: Parse.ProjectType -> FilePath -> IO Src.Module
parseModuleFile projType path = do
  content <- readSourceWithLimit path
  case Parse.fromByteString projType content of
    Left err -> InternalError.report
      "Compiler.Discovery.parseModuleFile"
      ("Failed to parse module: " <> Text.pack path)
      ("Parse error while discovering transitive dependencies: " <> Text.pack (show err))
    Right m -> return m
```

Called by `discoverTransitiveDeps` (line 74) on every initial path.

**Site 2: `parseModuleAtPath`** (lines 147-155)

```haskell
-- /home/quinten/fh/canopy/packages/canopy-builder/src/Compiler/Discovery.hs:147-155
parseModuleAtPath :: Parse.ProjectType -> (ModuleName.Raw, FilePath) -> IO Src.Module
parseModuleAtPath projectType (_modName, path) = do
  content <- readSourceWithLimit path
  case Parse.fromByteString projectType content of
    Left err -> InternalError.report
      "Compiler.Discovery.parseModuleAtPath"
      ("Failed to parse: " <> Text.pack path)
      ("Parse error: " <> Text.pack (show err))
    Right m -> return m
```

Called by `discoverOneModule` (line 136) for every newly discovered import.

### How the Build Pipeline Handles Parse Errors Elsewhere

The main `Builder.hs` already handles parse failures gracefully:

```haskell
-- /home/quinten/fh/canopy/packages/canopy-builder/src/Builder.hs:232-233
case Parse.fromByteString Parse.Application sourceBytes of
  Left parseErr -> return (Left (path ++ ": " ++ show parseErr))
  Right sourceModule -> return (Right (path, sourceModule))
```

And `getModuleDependencies` (Builder.hs:433-434) returns an empty list on
parse failure, silently skipping the module:

```haskell
case Parse.fromByteString Parse.Application sourceBytes of
  Left _ -> return []
  Right sourceModule -> ...
```

The Discovery module should follow the `Builder.parseModuleFromPath` pattern:
return `Either` with a structured error rather than crashing.

### Impact

Any file with a syntax error that is transitively imported by a project
causes a compiler crash with an "INTERNAL COMPILER ERROR" message, including
a bug-report URL.  This is confusing because it is not a compiler bug -- it is
a user error that should produce a clear parse error message with source
location.

## Files to Modify

### 1. `packages/canopy-builder/src/Compiler/Discovery.hs`

#### Change return type of `discoverTransitiveDeps`

**Current signature (line 65-71):**

```haskell
discoverTransitiveDeps ::
  FilePath ->
  [SrcDir] ->
  [FilePath] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Parse.ProjectType ->
  IO (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw]))
```

**Proposed signature:**

```haskell
discoverTransitiveDeps ::
  FilePath ->
  [SrcDir] ->
  [FilePath] ->
  Map.Map ModuleName.Raw Interface.Interface ->
  Parse.ProjectType ->
  IO (Either DiscoveryError (Map.Map ModuleName.Raw (FilePath, [ModuleName.Raw])))
```

#### Add `DiscoveryError` type

```haskell
-- | Errors that can occur during module discovery.
--
-- @since 0.19.2
data DiscoveryError
  = DiscoveryParseError !FilePath !Text.Text
    -- ^ A source file failed to parse during import discovery.
    -- Contains the file path and a textual description of the parse error.
  deriving (Eq, Show)
```

#### Change `parseModuleFile` to return `Either`

**Current (lines 82-90):**

```haskell
parseModuleFile :: Parse.ProjectType -> FilePath -> IO Src.Module
parseModuleFile projType path = do
  content <- readSourceWithLimit path
  case Parse.fromByteString projType content of
    Left err -> InternalError.report
      "Compiler.Discovery.parseModuleFile"
      ("Failed to parse module: " <> Text.pack path)
      ("Parse error while discovering transitive dependencies: " <> Text.pack (show err))
    Right m -> return m
```

**Proposed:**

```haskell
parseModuleFile :: Parse.ProjectType -> FilePath -> IO (Either DiscoveryError Src.Module)
parseModuleFile projType path = do
  content <- readSourceWithLimit path
  return (case Parse.fromByteString projType content of
    Left err -> Left (DiscoveryParseError path (Text.pack (show err)))
    Right m -> Right m)
```

#### Change `parseModuleAtPath` to return `Either`

**Current (lines 147-155):**

```haskell
parseModuleAtPath :: Parse.ProjectType -> (ModuleName.Raw, FilePath) -> IO Src.Module
parseModuleAtPath projectType (_modName, path) = do
  content <- readSourceWithLimit path
  case Parse.fromByteString projectType content of
    Left err -> InternalError.report ...
    Right m -> return m
```

**Proposed:**

```haskell
parseModuleAtPath :: Parse.ProjectType -> (ModuleName.Raw, FilePath) -> IO (Either DiscoveryError Src.Module)
parseModuleAtPath projectType (_modName, path) = do
  content <- readSourceWithLimit path
  return (case Parse.fromByteString projectType content of
    Left err -> Left (DiscoveryParseError path (Text.pack (show err)))
    Right m -> Right m)
```

#### Update `discoverTransitiveDeps` to propagate errors

**Current (lines 72-79):**

```haskell
discoverTransitiveDeps root srcDirs initialPaths depInterfaces projectType = do
  ...
  initialModules <- mapM (parseModuleFile projectType) initialPaths
  ...
```

**Proposed:**

```haskell
discoverTransitiveDeps root srcDirs initialPaths depInterfaces projectType = do
  Log.logEvent (BuildStarted (Text.pack ("discoverTransitiveDeps: " ++ root)))
  initialResults <- mapM (parseModuleFile projectType) initialPaths
  case partitionEithers initialResults of
    (err : _, _) -> return (Left err)
    ([], initialModules) -> do
      Log.logEvent (BuildModuleQueued ...)
      let initialMap = Map.fromList [...]
      result <- discoverImports root srcDirs initialMap Set.empty initialModules depInterfaces projectType
      ...
      return (Right result)
```

This requires adding `import Data.Either (partitionEithers)` or using a manual fold.

#### Update `discoverOneModule` to handle parse errors

**Current (line 136):**

```haskell
newModules <- mapM (parseModuleAtPath projectType) validPairs
```

**Proposed:**

```haskell
newResults <- mapM (parseModuleAtPath projectType) validPairs
```

Then propagate the `Either` through `discoverImports` and `discoverOneModule`
by threading the error.  The simplest approach is to make `discoverImports`
return `IO (Either DiscoveryError (Map ...))` and short-circuit on the first
parse error.

#### Update module exports

Add `DiscoveryError(..)` to the module export list.

### 2. `packages/canopy-builder/src/Compiler.hs` -- update caller

**Current (line 100):**

```haskell
allModuleInfo <- discoverTransitiveDeps root srcDirs paths depInterfaces projectType
```

**Proposed:**

```haskell
discoveryResult <- discoverTransitiveDeps root srcDirs paths depInterfaces projectType
case discoveryResult of
  Left (DiscoveryParseError path msg) ->
    return (Left (Exit.BuildErrorParse path msg))
  Right allModuleInfo -> do
    ...
```

This requires adding a new constructor to `Exit.BuildError` or mapping to an
existing one.  Check the current `Exit.BuildError` type:

```haskell
-- Check what constructors Exit.BuildError has
```

If there is already a parse-error constructor, map to it.  Otherwise, add
`BuildErrorDiscoveryParse !FilePath !Text` to the `BuildError` type.

### 3. `packages/canopy-builder/src/Reporting/Exit.hs` (if needed)

Add a parse-error variant to `BuildError` if one does not already exist for
the discovery phase.

### 4. Export updates in `Compiler/Discovery.hs`

Update the module export list (lines 16-33) to include:

```haskell
    -- * Error Types
    DiscoveryError (..),
```

## Verification

### Unit Tests

Create `test/Unit/Compiler/DiscoveryTest.hs` with:

```haskell
testParseFailureReturnsLeft :: TestTree
testParseFailureReturnsLeft =
  testCase "parseModuleFile returns Left on invalid source" $ do
    -- Write a file with invalid Canopy syntax
    let path = "/tmp/canopy-test-bad-syntax.can"
    BS.writeFile path "module Main exposing (..)\n\ninvalid syntax @@@ !!!"
    result <- Discovery.parseModuleFile Parse.Application path
    assertBool "expected Left for parse failure" (isLeft result)

testParseSuccessReturnsRight :: TestTree
testParseSuccessReturnsRight =
  testCase "parseModuleFile returns Right on valid source" $ do
    let path = "/tmp/canopy-test-good.can"
    BS.writeFile path "module Main exposing (..)\n\nmain = 42\n"
    result <- Discovery.parseModuleFile Parse.Application path
    assertBool "expected Right for valid source" (isRight result)
```

### Integration Test

Create a test project with a file containing a syntax error in an import:

```bash
mkdir -p /tmp/canopy-parse-error-test/src
echo 'module Main exposing (..)\nimport Broken\nmain = 1' > /tmp/canopy-parse-error-test/src/Main.can
echo 'module Broken exposing (..)\n\n@@@ invalid' > /tmp/canopy-parse-error-test/src/Broken.can
```

Run the compiler and verify it produces a parse error (not a crash):

```bash
# Should exit with parse error, NOT "INTERNAL COMPILER ERROR"
canopy make src/Main.can 2>&1 | grep -v "INTERNAL COMPILER ERROR"
echo $?  # Should be non-zero but not a signal
```

### Build Verification

```bash
# Ensure no warnings
stack build --ghc-options="-Wall -Werror" 2>&1

# Full test suite
stack test
```

## Rollback Plan

Revert the `Discovery.hs`, `Compiler.hs`, and `Exit.hs` changes.  The functions
revert to calling `InternalError.report` on parse failure.  No data format
or interface changes.
