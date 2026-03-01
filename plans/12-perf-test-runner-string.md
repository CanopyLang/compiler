# Plan 12: Test Runner String Processing

**Priority:** HIGH
**Effort:** Small (4-6 hours)
**Risk:** Low (isolated to test command, no compiler core changes)

## Problem

The test runner in `Test.hs` converts the entire JavaScript output to `String` for
post-processing, then passes it around as `String` through the rest of the pipeline.
This is the single largest memory allocation in the test command.

### Current Data Flow

```
Compiler.Artifacts
  -> JS.generate (returns Builder)
  -> builderToString (allocates full [Char] of entire JS bundle)
  -> postProcessJavaScript (character-by-character String replacement)
  -> String passed through 6+ function calls
  -> Text.pack jsContent (re-encodes to Text)
  -> Text.unpack (converts back to String for writeFile)
```

### Affected Code

**`/home/quinten/fh/canopy/packages/canopy-terminal/src/Test.hs`:**

Line 300: Return type uses `String`:
```haskell
compileTestFiles :: FilePath -> [FilePath] -> IO (Maybe (String, Map.Map ModuleName.Canonical Opt.Main))
```

Lines 434-442: `artifactsToJavaScript` converts Builder to String:
```haskell
artifactsToJavaScript :: Compiler.Artifacts -> String
artifactsToJavaScript artifacts =
  postProcessJavaScript rawJs
  where
    globalGraph = artifacts ^. Build.artifactsGlobalGraph
    ffiInfo = artifacts ^. Build.artifactsFFIInfo
    mains = collectMains artifacts
    (builder, _sourceMap) = JS.generate (Mode.Dev Nothing False False False Set.empty) globalGraph mains ffiInfo
    rawJs = builderToString builder
```

Lines 445-454: `postProcessJavaScript` does character-by-character String replacement:
```haskell
postProcessJavaScript :: String -> String
postProcessJavaScript js =
  replace "elseif" "else if" js
  where
    replace old new = go
      where
        go [] = []
        go str@(x : xs)
          | old `List.isPrefixOf` str = new ++ go (drop (length old) str)
          | otherwise = x : go xs
```

Lines 472-475: `builderToString` byte-by-byte conversion:
```haskell
builderToString :: Builder.Builder -> String
builderToString b =
  map (toEnum . fromIntegral) (LBS.unpack (Builder.toLazyByteString b))
```

### String Propagation Through the Pipeline

The `String` type propagates through all test execution paths:

- Line 485: `dispatchByTestType :: String -> ...` receives it
- Line 515: `executeBrowserExecutionTests :: String -> ...`
- Line 548: `JsContent (Text.pack jsContent)` -- re-encodes to Text
- Line 605: `executeUnitTests :: String -> ...`
- Line 610: `JsContent (Text.pack jsContent)` -- re-encodes to Text
- Line 625: `executeBrowserTests :: String -> ...`
- Line 682: `JsContent (Text.pack jsContent)` -- re-encodes to Text

Every single branch converts the `String` to `Text.pack jsContent` immediately.

### The "elseif" Problem

The `postProcessJavaScript` function exists to fix a `language-javascript` rendering
quirk where `else if` is emitted as `elseif`. This is a 6-character pattern match
done character-by-character over the entire JS output (potentially megabytes).

## Solution

### Phase 1: Replace String with ByteString/Text throughout

Change the pipeline to use `ByteString` (from the Builder) and perform the
replacement at the `ByteString` level:

```haskell
-- BEFORE (line 300)
compileTestFiles :: FilePath -> [FilePath] -> IO (Maybe (String, Map.Map ModuleName.Canonical Opt.Main))

-- AFTER
compileTestFiles :: FilePath -> [FilePath] -> IO (Maybe (Text.Text, Map.Map ModuleName.Canonical Opt.Main))
```

```haskell
-- BEFORE (lines 434-442)
artifactsToJavaScript :: Compiler.Artifacts -> String
artifactsToJavaScript artifacts =
  postProcessJavaScript rawJs
  where
    ...
    rawJs = builderToString builder

-- AFTER
artifactsToJavaScript :: Compiler.Artifacts -> Text.Text
artifactsToJavaScript artifacts =
  postProcessJavaScript rawText
  where
    globalGraph = artifacts ^. Build.artifactsGlobalGraph
    ffiInfo = artifacts ^. Build.artifactsFFIInfo
    mains = collectMains artifacts
    (builder, _sourceMap) = JS.generate (Mode.Dev Nothing False False False Set.empty) globalGraph mains ffiInfo
    rawText = TextEnc.decodeUtf8 (LBS.toStrict (Builder.toLazyByteString builder))
```

### Phase 2: Replace character-by-character replacement with Text.replace

```haskell
-- BEFORE (lines 445-454)
postProcessJavaScript :: String -> String
postProcessJavaScript js =
  replace "elseif" "else if" js
  where
    replace old new = go
      where
        go [] = []
        go str@(x : xs)
          | old `List.isPrefixOf` str = new ++ go (drop (length old) str)
          | otherwise = x : go xs

-- AFTER
postProcessJavaScript :: Text.Text -> Text.Text
postProcessJavaScript = Text.replace "elseif" "else if"
```

### Phase 3: Update all downstream call sites

Change all functions that receive the JS content to use `Text.Text` instead of
`String`:

```haskell
-- Line 485
dispatchByTestType :: Text.Text -> Map.Map ModuleName.Canonical Opt.Main -> [FilePath] -> Flags -> IO ExitCode

-- Line 515
executeBrowserExecutionTests :: Text.Text -> [FilePath] -> Flags -> IO ExitCode

-- Line 605
executeUnitTests :: Text.Text -> Flags -> IO ExitCode

-- Line 625
executeBrowserTests :: Text.Text -> [FilePath] -> Flags -> IO ExitCode
```

The downstream code already converts to `JsContent (Text.pack jsContent)`, so with
`Text.Text` input the conversion becomes simply `JsContent jsContent` (no-op).

### Phase 4: Remove `builderToString`

Delete the `builderToString` function entirely (lines 472-475) and the unused import
of `Data.ByteString.Lazy`.

### Phase 5 (optional): Fix at the source

Investigate whether the `elseif` problem comes from the `language-javascript` fork's
pretty printer or from Canopy's own `Builder.hs` AST construction. If it comes from
`Builder.hs` line 287's `JS.JSIfElse` construction, fix the AST construction to emit
proper `else if` blocks and eliminate `postProcessJavaScript` entirely.

## Files to Modify

| File | Change |
|------|--------|
| `packages/canopy-terminal/src/Test.hs` | Replace `String` with `Text.Text` throughout; replace `builderToString` with direct `Text` decoding; replace character-by-character replacement with `Text.replace`; remove `builderToString` |

## Verification

```bash
# Run test suite to verify test command still works
stack test --ta="--pattern Test"

# Run the actual test command on a sample project
cd /path/to/sample-project && canopy test

# Profile memory usage improvement
canopy test +RTS -s -RTS 2>&1 | grep "total memory"
```

## Expected Impact

- Eliminates `[Char]` allocation of the entire JS bundle (potentially megabytes)
- `Text.replace` is O(n) with efficient ByteString-backed Text, vs O(n*m) for the
  character-by-character `isPrefixOf` approach
- Removes 6 redundant `Text.pack`/`Text.unpack` conversions in the test pipeline
- Expected 50-80% reduction in test command peak memory for large projects
- Expected 20-40% wall-clock improvement in test compilation+execution phase
