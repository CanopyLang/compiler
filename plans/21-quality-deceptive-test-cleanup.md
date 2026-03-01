# Plan 21: Deceptive Test Cleanup

**Priority:** HIGH
**Effort:** Medium (1-2d)
**Risk:** Low -- Removing/replacing tests does not affect production code

## Problem

The test suite contains numerous deceptive tests that appear to verify behavior but actually test nothing meaningful. These waste CI time, give false confidence in code quality, and violate the project's own testing standards defined in `CLAUDE.md`.

### Category 1: TODO/Stub Tests

**File:** `/home/quinten/fh/canopy/test/Integration/CompilerTest.hs`

Lines 20-37 -- `testSimpleCanopyCompilation` writes a file and only checks it exists:
```haskell
testSimpleCanopyCompilation =
  testCase "compile simple Canopy module" . withSystemTempDirectory "canopy-test" $
    ( \tmpDir -> do
        let canopyFile = tmpDir </> "Main.canopy"
        writeFile canopyFile simpleCanopyModule
        let canopyJson = tmpDir </> "canopy.json"
        writeFile canopyJson simpleCanopyJsonApplication
        -- TODO: Add actual compilation test when we understand the Compile module better
        -- For now, just test that the files exist
        doesExist <- doesFileExist canopyFile
        doesExist @? "Canopy file should exist"
        jsonExists <- doesFileExist canopyJson
        jsonExists @? "canopy.json should exist"
    )
```

Lines 41-48 -- `testCanopyJsonParsing` similarly only checks file existence:
```haskell
testCanopyJsonParsing =
  testCase "parse canopy.json files" . withSystemTempDirectory "canopy-json-test" $
    ( \tmpDir -> do
        let canopyJson = tmpDir </> "canopy.json"
        writeFile canopyJson simpleCanopyJsonPackage
        jsonExists <- doesFileExist canopyJson
        jsonExists @? "canopy.json should exist"
    )
```

Line 50: `-- TODO: Add actual JSON parsing tests`

These test only `writeFile` + `doesFileExist`, which is testing the OS filesystem, not the compiler.

### Category 2: Reflexive Equality Tests

**File:** `/home/quinten/fh/canopy/test/Unit/InstallTest.hs`

Lines 40-41 -- Testing `NoArgs @?= NoArgs` (a value equals itself):
```haskell
testCase "NoArgs constructor" $
    NoArgs @?= NoArgs,
```

Lines 52-57 -- Testing that constructing the same value twice gives the same result:
```haskell
testCase "NoArgs equals NoArgs" $
    NoArgs == NoArgs @?= True,
testCase "Install with same package equals" $ do
    let pkg1 = Pkg.core
    let pkg2 = Pkg.core
    Install pkg1 == Install pkg2 @?= True,
```

Lines 186-188 -- Pattern matching `NoArgs` then asserting `NoArgs @?= NoArgs`:
```haskell
case noArgs of
  NoArgs -> noArgs @?= NoArgs
  _ -> assertFailure "NoArgs should match NoArgs pattern"
```

These test Haskell's `deriving Eq` and basic pattern matching, not the Install module.

### Category 3: Weak Assertion Patterns

**File:** `/home/quinten/fh/canopy/test/Unit/InstallTest.hs`

Line 73 -- Testing `length (show x) > 0` (the Show instance produces non-empty output):
```haskell
testCase "NoArgs show is not empty" $
    assertBool "NoArgs should have meaningful show output" (length (show NoArgs) > 0),
```

Line 77 -- Testing that `"Install"` appears in the show output of `Install`:
```haskell
testCase "Install show contains package info" $ do
    let pkg = Pkg.core
    let output = show (Install pkg)
    assertBool "Install show should contain 'Install'" ("Install" `elem` words output)
```

### Category 4: Mock Functions

**File:** `/home/quinten/fh/canopy/test/Unit/Queries/ParseModuleTest.hs`

Line 209 -- A function that always returns True, labeled "simplified for test":
```haskell
hasExports :: Src.Module -> Bool
hasExports _ = True -- Simplified for test
```

**File:** `/home/quinten/fh/canopy/test/Unit/Terminal/ChompTest.hs`

Line 186 -- A function that always succeeds, labeled "simplified for testing":
```haskell
try :: a -> Either String a
try x = Right x -- Simplified for testing - in real code would catch errors
```

### Category 5: Weak isInfixOf/containsStr Assertions

Multiple test files use `isInfixOf`/`containsStr` checks instead of exact value assertions:

**File:** `/home/quinten/fh/canopy/test/Unit/Logging/SinkTest.hs` (lines 63-112):
```haskell
Text.isInfixOf "INFO" content @?= True,
Text.isInfixOf "PARSE" content @?= True,
Text.isInfixOf "my-unique-label" content @?= True
```

**File:** `/home/quinten/fh/canopy/test/Unit/Watch/LiveReloadTest.hs` (lines 37-80):
```haskell
(Text.isInfixOf "ws://localhost:8234" script),
(Text.isInfixOf "location.reload()" script),
```

**File:** `/home/quinten/fh/canopy/test/Integration/MakeTest.hs` (line 242):
```haskell
assertBool "development modules have string representations"
  (all (\m -> length (show m) > 0) devModules)
```

**File:** `/home/quinten/fh/canopy/test/Unit/Terminal/Error/TypesTest.hs` (lines 155-157):
```haskell
assertBool "ArgMissing produces output" (length (show missingError) > 5)
assertBool "ArgBad produces output" (length (show badError) > 5)
assertBool "ArgExtras produces output" (length (show extrasError) > 5)
```

**File:** `/home/quinten/fh/canopy/test/Unit/Terminal/Error/FormattingTest.hs` (lines 74-94):
```haskell
assertBool "Flag formatting produces documentation" (length (show result) > length ("output" ++ "file")),
assertBool "Argument formatting enhances readability" (length (show result) > length ("input" :: String))
assertBool "Examples list produces structured output" (length (show result) > sum (map length examples)),
```

### Category 6: isPrefixOf Helper Stubs

**File:** `/home/quinten/fh/canopy/test/Integration/CodeSplitIntegrationTest.hs` (line 128):
```haskell
isPrefixOfStr [] _ = True
```

**File:** `/home/quinten/fh/canopy/test/Unit/Reporting/ErrorHierarchyTest.hs` (line 215):
```haskell
isPrefixOf [] _ = True
```

**File:** `/home/quinten/fh/canopy/test/Unit/Builder/CacheVersionTest.hs` (line 112):
```haskell
isPrefixOfStr [] _ = True
```

These are legitimate helpers for prefix matching but should use `Data.List.isPrefixOf` instead.

## Catalog of Deceptive Tests to Fix

| File | Test Name | Issue | Fix |
|------|-----------|-------|-----|
| `test/Integration/CompilerTest.hs` | `testSimpleCanopyCompilation` | TODO stub, only tests filesystem | Replace with actual `Compiler.compileFromPaths` call |
| `test/Integration/CompilerTest.hs` | `testCanopyJsonParsing` | TODO stub, only tests filesystem | Replace with `Outline.decode` parsing test |
| `test/Unit/InstallTest.hs` | `testArgsDataType` | `NoArgs @?= NoArgs` reflexive | Test actual Args construction and extraction behavior |
| `test/Unit/InstallTest.hs` | `testArgsEquality` | Tests `deriving Eq`, not business logic | Replace with meaningful equality edge cases |
| `test/Unit/InstallTest.hs` | `testArgsShow` | `length (show x) > 0` | Test exact show output: `show NoArgs @?= "NoArgs"` |
| `test/Unit/InstallTest.hs` | `testContextOperations` | Redundant pattern matching tests | Replace with actual install workflow tests |
| `test/Unit/Queries/ParseModuleTest.hs` | `hasExports` helper | `_ = True` mock | Implement real export checking |
| `test/Unit/Terminal/ChompTest.hs` | `try` helper | `_ = Right x` mock | Implement real error handling |
| `test/Unit/Terminal/Error/TypesTest.hs` | `ArgMissing produces output` | `length (show x) > 5` | Test exact error content |
| `test/Unit/Terminal/Error/FormattingTest.hs` | Multiple | `length (show x) > length ...` | Test exact formatted output |
| `test/Integration/MakeTest.hs:242` | module string check | `length (show m) > 0` | Test actual module content |
| `test/Unit/Logging/SinkTest.hs` | Multiple | `isInfixOf` checks | Test exact log format structure |

## Proposed Fixes

### CompilerTest.hs -- Replace Stubs with Real Tests

```haskell
testSimpleCanopyCompilation :: TestTree
testSimpleCanopyCompilation =
  testCase "compile simple Canopy module" . withSystemTempDirectory "canopy-test" $
    ( \tmpDir -> do
        let canopyFile = tmpDir </> "src" </> "Main.can"
        createDirectoryIfMissing True (tmpDir </> "src")
        writeFile canopyFile simpleCanopyModule
        writeFile (tmpDir </> "canopy.json") simpleCanopyJsonApplication

        result <- Compiler.compileFromPaths
          Pkg.dummyName True
          (Compiler.ProjectRoot tmpDir)
          [Compiler.RelativeSrcDir "src"]
          [canopyFile]

        case result of
          Left err -> assertFailure ("Compilation failed: " ++ show err)
          Right artifacts -> length (Compiler.artifactModules artifacts) @?= 1
    )
```

### InstallTest.hs -- Replace Reflexive Tests with Behavioral Tests

```haskell
testArgsDataType :: TestTree
testArgsDataType =
  testGroup "Args data type"
    [ testCase "NoArgs show output" $
        show NoArgs @?= "NoArgs",
      testCase "Install show output contains package" $
        show (Install Pkg.core) @?= "Install " ++ show Pkg.core,
      testCase "Install carries exact package" $
        extractPackage (Install Pkg.json) @?= Just Pkg.json,
      testCase "NoArgs carries no package" $
        extractPackage NoArgs @?= Nothing,
      testCase "different packages produce different Args" $
        Install Pkg.core /= Install Pkg.json @?= True
    ]
```

### ParseModuleTest.hs -- Implement Real hasExports

```haskell
hasExports :: Src.Module -> Bool
hasExports modul =
  case Src._exports modul of
    Ann.At _ Src.Open -> True
    Ann.At _ (Src.Explicit items) -> not (null items)
```

## Files to Modify

| File | Change |
|------|--------|
| `test/Integration/CompilerTest.hs` | Replace TODO stubs with actual compilation tests |
| `test/Unit/InstallTest.hs` | Replace reflexive/weak tests with exact-value assertions |
| `test/Unit/Queries/ParseModuleTest.hs` | Replace `hasExports _ = True` with real implementation |
| `test/Unit/Terminal/ChompTest.hs` | Replace `try x = Right x` with real implementation |
| `test/Unit/Terminal/Error/TypesTest.hs` | Replace `length (show x) > N` with exact assertions |
| `test/Unit/Terminal/Error/FormattingTest.hs` | Replace `length (show x) > length ...` with exact assertions |
| `test/Integration/MakeTest.hs` | Replace `length (show m) > 0` with meaningful assertion |
| `test/Unit/Logging/SinkTest.hs` | Consider keeping isInfixOf for log format (acceptable for logs) |

## Verification

```bash
# 1. All tests still pass after fixes
make test

# 2. Verify no mock functions remain
grep -rn "_ = True\|_ = False" test/ --include="*.hs" | grep -v "Golden/expected" | grep -v ".md"
# Should return 0 matches (excluding golden test expected output and docs)

# 3. Verify no reflexive equality
grep -rn "@?= NoArgs" test/ --include="*.hs"
# Should only appear in tests that verify function results, not `x @?= x`

# 4. Verify no weak length checks
grep -rn "length (show" test/ --include="*.hs" | grep "> 0\|> [0-9]"
# Should return 0 matches

# 5. Verify no TODO stubs
grep -rn "TODO.*test\|TODO.*Add" test/ --include="*.hs"
# Should return 0 matches (excluding golden expected output)

# 6. Run with coverage to verify tests actually exercise code
make test-coverage
```

## Notes

Some `isInfixOf` patterns are acceptable for testing log output or HTML fragments (e.g., `HtmlSecurityTest.hs` checking for CSP headers). The distinction is:
- **Deceptive:** `assertBool "show produces output" (length (show x) > 0)` -- tests nothing about x
- **Acceptable:** `assertBool "CSP meta tag present" (containsCSP output)` -- tests security-relevant content presence

The logging sink tests (`SinkTest.hs`) are borderline -- `isInfixOf` checks for log format are reasonable since exact log format is implementation detail. These should be reviewed case-by-case.
