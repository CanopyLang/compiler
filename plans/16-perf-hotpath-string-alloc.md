# Plan 16: Hot-Path String Allocations

**Priority:** HIGH
**Effort:** Small (4-6 hours)
**Risk:** Low (all changes are internal representation swaps, no output changes)

## Problem

Several hot paths in code generation and FFI processing allocate `String` (`[Char]`)
values for operations that could be performed directly on the underlying `Utf8`
ByteString or `Text`. These are called once per global definition or once per FFI
function, making them significant contributors to allocation during compilation.

### Hot Path 1: Kernel Module Detection (per global)

**`/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript.hs`:**

Line 343: `resolveAltGlobal` is called for every global that is not found in the
graph. It converts `Name` to `String` to do a prefix check:

```haskell
isKernelModule = "Kernel." `List.isPrefixOf` Name.toChars moduleName
```

`Name.toChars` allocates a full `[Char]` list from the Utf8 ByteArray. The
`Utf8.startsWith` function (used in `Canopy.Data.Name.Kernel`) performs the same
check at the byte level with zero allocation.

Line 355: Strips the "Kernel." prefix via `drop 7` on String:

```haskell
let kernelName = drop 7 (Name.toChars moduleName)
```

Then converts back with `Name.fromChars kernelName` -- round-trip through String.

Line 359: Prepends "Kernel." prefix via String concatenation:

```haskell
let kernelModuleName = "Kernel." ++ Name.toChars moduleName
```

Then converts back with `Name.fromChars kernelModuleName`.

### Hot Path 2: FFI Alias to String (per FFI module)

**`/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/FFI.hs`:**

Line 209: Converts FFI alias Name to String for all subsequent operations:

```haskell
alias = Name.toChars (_ffiAlias info)
```

This `String` is then used in:
- `isValidJsIdentifier alias` (line 198) -- character-by-character check
- `Name.toChars` appears in multiple builder operations throughout the function

### Hot Path 3: FFI @canopy-type Parsing (per JS source line)

**`/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/FFI.hs`:**

Lines 233-238: `extractCanopyType` uses `List.isInfixOf` on every line of FFI JS:

```haskell
extractCanopyType :: String -> Maybe String
extractCanopyType line =
  if " * @canopy-type " `List.isInfixOf` line
    then case dropWhile (/= '@') line of
      ('@':'c':'a':'n':'o':'p':'y':'-':'t':'y':'p':'e':' ':typeStr) -> Just (trim typeStr)
      _ -> Nothing
    else Nothing
```

`List.isInfixOf` is O(n*m) for `String`. For FFI files with hundreds of lines,
this is significant.

Lines 245-252: `findFunctionName` uses `List.isPrefixOf` on String:

```haskell
findFunctionName :: [String] -> Maybe String
findFunctionName (line:rest) =
  let trimmed = trim line
      stripped = stripAsyncPrefix trimmed
  in if "function " `List.isPrefixOf` stripped
       then extractNameAfterFunction stripped
       else if "*/" `List.isInfixOf` line
         then findFunctionName rest
         else findFunctionName rest
```

### Hot Path 4: VarGlobal FFI Name Construction (per FFI reference)

**`/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/Expression.hs`:**

Lines 95-98: For every FFI global reference, allocates two Strings and concatenates:

```haskell
Opt.VarGlobal (Opt.Global home name) ->
  let moduleName = ModuleName._module home
   in if Mode.isFFIAlias mode moduleName
        then
          let moduleStr = Name.toChars moduleName
              nameStr = Name.toChars name
              jsName = Name.fromChars (moduleStr ++ "." ++ nameStr)
           in JsExpr $ JS.Ref (JsName.fromLocal jsName)
```

This allocates two `[Char]` lists and a third for the concatenation, then converts
back to `Name`. The entire operation could use `Name.toBuilder` and Builder
concatenation.

### Hot Path 5: Minify Short Name Generation

**`/home/quinten/fh/canopy/packages/canopy-core/src/Generate/JavaScript/Minify.hs`:**

Line 179: Recursively converts Name to String and back:

```haskell
Name.fromChars (Name.toChars (shortName (q - 1)) ++ [toEnum (fromEnum 'a' + r)])
```

## Solution

### Fix 1: Kernel Module Detection -- Use Utf8.startsWith

```haskell
-- Add a "Kernel." prefix constant
{-# NOINLINE kernelDotPrefix #-}
kernelDotPrefix :: Name.Name
kernelDotPrefix = "Kernel."

-- BEFORE (line 343)
isKernelModule = "Kernel." `List.isPrefixOf` Name.toChars moduleName

-- AFTER
isKernelModule = Utf8.startsWith kernelDotPrefix moduleName
```

For the prefix stripping (line 355), add a `Utf8.dropPrefix` function:

```haskell
-- In Canopy/Data/Utf8.hs or Canopy/Data/Utf8/Manipulation.hs
-- | Drop the first n bytes from a Utf8 value.
dropBytes :: Int -> Utf8 a -> Utf8 a

-- BEFORE (line 355)
let kernelName = drop 7 (Name.toChars moduleName)

-- AFTER
let kernelName = Utf8.dropBytes 7 moduleName
```

For the prefix prepending (line 359), use Builder concatenation:

```haskell
-- BEFORE (line 359)
let kernelModuleName = "Kernel." ++ Name.toChars moduleName

-- AFTER: Use a Utf8 concatenation function or Builder
let kernelModuleName = Name.fromChars ("Kernel." ++ Name.toChars moduleName)
-- Better: add Utf8.append or use Builder:
let kernelModuleName = Utf8.fromBuilder (BB.byteString "Kernel." <> Name.toBuilder moduleName)
```

### Fix 2: FFI Alias -- Use Text Operations

Since `_ffiContent` is already `Text.Text`, and the FFI processing works on Text
content, convert the alias to Text once and use Text operations:

```haskell
-- BEFORE (line 209)
alias = Name.toChars (_ffiAlias info)

-- AFTER: Use Text directly where possible, or keep as Name
aliasName = _ffiAlias info
aliasBuilder = Name.toBuilder aliasName
```

For `isValidJsIdentifier`, add a ByteString-aware version or operate on the
`Name` directly using `Utf8` byte access.

### Fix 3: FFI @canopy-type Parsing -- Use Text Operations

Since `_ffiContent` is `Text.Text`, parse the FFI content as Text instead of
converting to `[String]`:

```haskell
-- BEFORE (line 153-154)
let contentStr = Text.unpack (_ffiContent info)
    functions = extractCanopyTypeFunctions (lines contentStr)

-- AFTER
let functions = extractCanopyTypeFunctionsText (Text.lines (_ffiContent info))
```

Then rewrite `extractCanopyType` using `Text.isInfixOf` (O(n) with Boyer-Moore)
instead of `List.isInfixOf` (O(n*m)):

```haskell
extractCanopyTypeText :: Text.Text -> Maybe Text.Text
extractCanopyTypeText line
  | " * @canopy-type " `Text.isInfixOf` line =
      case Text.stripPrefix "@canopy-type " (Text.dropWhile (/= '@') line) of
        Just typeStr -> Just (Text.strip typeStr)
        Nothing -> Nothing
  | otherwise = Nothing
```

### Fix 4: VarGlobal FFI Name -- Use Builder Concatenation

```haskell
-- BEFORE (lines 95-98)
let moduleStr = Name.toChars moduleName
    nameStr = Name.toChars name
    jsName = Name.fromChars (moduleStr ++ "." ++ nameStr)

-- AFTER: Build directly with Builders, avoid String round-trip
let jsName = Utf8.fromBuilder (Name.toBuilder moduleName <> BB.char7 '.' <> Name.toBuilder name)
```

Or add a `Name.joinWithDot :: Name -> Name -> Name` utility.

### Fix 5: Minify Short Name -- Use Builder

```haskell
-- BEFORE (line 179)
Name.fromChars (Name.toChars (shortName (q - 1)) ++ [toEnum (fromEnum 'a' + r)])

-- AFTER
Utf8.fromBuilder (Name.toBuilder (shortName (q - 1)) <> BB.char7 (toEnum (fromEnum 'a' + r)))
```

## Files to Modify

| File | Change |
|------|--------|
| `packages/canopy-core/src/Generate/JavaScript.hs` | Replace `Name.toChars` + `isPrefixOf`/`drop`/`++` with `Utf8.startsWith`/`dropBytes`/Builder concatenation (lines 343, 355, 359) |
| `packages/canopy-core/src/Generate/JavaScript/Expression.hs` | Replace `Name.toChars` + String concat with Builder concat (lines 95-98) |
| `packages/canopy-core/src/Generate/JavaScript/FFI.hs` | Replace String-based `isInfixOf`/`isPrefixOf` with Text equivalents; operate on `Text` lines instead of `String` lines (lines 153, 209, 234, 248, 250) |
| `packages/canopy-core/src/Generate/JavaScript/Minify.hs` | Replace `Name.toChars`/`fromChars` round-trip with Builder (line 179) |
| `packages/canopy-core/src/Canopy/Data/Utf8/Manipulation.hs` | Add `dropBytes :: Int -> Utf8 a -> Utf8 a` and `fromBuilder :: Builder -> Utf8 a` utilities |

## Verification

```bash
# Run full test suite
make test

# Run golden tests for JS generation
stack test --ta="--pattern JsGen"

# Run FFI-related tests
stack test --ta="--pattern FFI"

# Profile allocation improvement
stack exec -- canopy make +RTS -s -RTS
stack bench --ba="--match prefix Bench.Generate"
```

## Expected Impact

- **Fix 1 (Kernel detection)**: Eliminates ~N `[Char]` allocations per module with
  unresolved globals (N = number of globals requiring alt-lookup). Constant factor
  improvement per call site.
- **Fix 2-3 (FFI parsing)**: Eliminates O(lines * pattern_length) String allocation
  per FFI file. For a typical FFI file with 200 lines, saves ~200 `[Char]` allocations.
  `Text.isInfixOf` is also algorithmically faster than `List.isInfixOf`.
- **Fix 4 (VarGlobal)**: Eliminates 3 `[Char]` allocations per FFI global reference.
  For a project with 50 FFI functions referenced 10 times each, saves ~1500 allocations.
- **Fix 5 (Minify)**: Eliminates String round-trip in minification name generation.
  Called once per minified name (~10,000 calls for a large project).
- **Combined**: Expected 5-10% reduction in codegen phase allocation for projects
  with FFI usage; 2-3% for pure Canopy projects.
