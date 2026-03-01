# Plan 04: Flow-Level FFI Type Checking — Static Analysis of JavaScript

**Priority**: CRITICAL
**Effort**: Large (2-3 weeks)
**Risk**: Medium
**Audit Finding**: FFI boundary is where Canopy's type safety completely breaks down. JavaScript functions can return any value; `--ffi-strict` runtime validation is opt-in. A JS function declared `@canopy-type Int` can return `"hello"` and Canopy silently accepts it.

---

## Problem

Canopy's type system is sound within Canopy code. The moment JavaScript enters through FFI, all guarantees disappear:

```javascript
// src/ffi/math.js
/** @canopy-type Int -> Int -> Int */
function add(a, b) { return a + b; }  // Works... but also accepts strings
```

```elm
-- Canopy code — type-checked, safe
result = FFI.add 1 "hello"  -- This SHOULD be caught!
```

**Current state:**
- `--ffi-strict` (opt-in): Runtime validators catch mismatches, but only at execution time
- `--ffi-unsafe` (default): No validation. JS returns whatever it wants.
- **No static analysis** of the JavaScript code itself

Facebook's Flow solves this by **statically analyzing JavaScript** and detecting patterns like `1 + ""` at compile time, before any code runs. Canopy should do the same for FFI files.

---

## Solution: Three-Layer FFI Type Safety

### Layer 1: Make Runtime Validation Default (not opt-in)

Flip the default: `--ffi-strict` is now the default. `--ffi-unsafe` is opt-in for performance-critical code.

### Layer 2: Static Analysis of FFI JavaScript Files

Parse and analyze the JavaScript FFI files at compile time to detect:
- Type inconsistencies between `@canopy-type` annotations and actual code
- Mixed-type operations (`1 + ""`, `null + number`)
- Missing return paths (function declared to return `Int` but has code paths returning `undefined`)
- Null/undefined leaking into non-Maybe return types
- Wrong `Result` tag construction (`{ $: 'Ok' }` vs bare values)
- Promise/callback mismatches

### Layer 3: FFI Type Inference

Infer types from JavaScript code and compare against declared `@canopy-type` annotations. Warn when inferred type doesn't match declared type.

---

## Implementation

### Step 1: Default to Strict Mode

**File: `packages/canopy-core/src/Generate/Mode.hs`**

```haskell
-- Before: ffiUnsafe defaults to True (no validation)
-- After: ffiUnsafe defaults to False (validation enabled)

data Mode = Mode
  { _modeType :: !ModeType
  , _modeFfiUnsafe :: !Bool  -- Default: False (strict)
  , _modeFfiDebug :: !Bool
  }

defaultMode :: ModeType -> Mode
defaultMode modeType = Mode
  { _modeType = modeType
  , _modeFfiUnsafe = False   -- CHANGED: strict by default
  , _modeFfiDebug = False
  }
```

**File: `packages/canopy-terminal/src/Make.hs`**

Update CLI flag description:

```haskell
-- --ffi-unsafe: Disable runtime type checking at FFI boundary (not recommended)
-- --ffi-strict: (default) Enable runtime type checking at FFI boundary
```

### Step 2: JavaScript Static Analyzer

**File: `packages/canopy-core/src/FFI/StaticAnalysis.hs`** (new module)

This is the core of the Flow-level detection. We analyze the JavaScript AST (already parsed by `language-javascript`) to detect type issues.

```haskell
-- | Static analysis of FFI JavaScript files.
-- Detects type inconsistencies between @canopy-type annotations
-- and actual JavaScript code, similar to Facebook's Flow type checker.
module FFI.StaticAnalysis
  ( analyzeFFIFile
  , FFIAnalysisResult (..)
  , FFIWarning (..)
  ) where

-- | Result of analyzing an FFI JavaScript file.
data FFIAnalysisResult = FFIAnalysisResult
  { _analysisWarnings :: ![FFIWarning]
  , _analysisErrors :: ![FFIError]
  , _analysisInferredTypes :: !(Map Text InferredType)
  }

-- | Warnings from FFI static analysis.
data FFIWarning
  = MixedTypeOperation !Region !Text !Text
    -- ^ e.g., "number + string" at line:col
  | NullableReturnWithoutMaybe !Region !Text
    -- ^ Function can return null/undefined but declared as non-Maybe
  | MissingReturnPath !Region !Text
    -- ^ Not all code paths return a value
  | TypeMismatch !Region !Text !InferredType !FFIType
    -- ^ Inferred type doesn't match declared @canopy-type
  | UnsafeCoercion !Region !Text !Text
    -- ^ Implicit type coercion (e.g., string to number via +)
  | ResultTagMissing !Region !Text
    -- ^ Returns value without { $: 'Ok'/'Err' } wrapper
  | PromiseNotReturned !Region !Text
    -- ^ Async function but @canopy-type doesn't use Task
  | ArrayElementTypeMixed !Region !Text
    -- ^ Array contains mixed types
  deriving (Eq, Show)

-- | Analyze an FFI JavaScript file for type safety issues.
analyzeFFIFile
  :: FilePath
  -> JSAST
  -> Map Text FFIType  -- declared @canopy-type annotations
  -> FFIAnalysisResult
analyzeFFIFile path ast declaredTypes =
  FFIAnalysisResult
    { _analysisWarnings = warnings
    , _analysisErrors = errors
    , _analysisInferredTypes = inferred
    }
  where
    warnings = concatMap (analyzeFunction declaredTypes) (extractFunctions ast)
    errors = concatMap (checkTypeConsistency declaredTypes inferred) (Map.toList declaredTypes)
    inferred = Map.fromList (map inferFunctionType (extractFunctions ast))
```

### Step 3: Expression-Level Type Inference for JavaScript

**File: `packages/canopy-core/src/FFI/StaticAnalysis/Infer.hs`** (new)

Infer types from JavaScript expressions (lightweight, not full Flow):

```haskell
-- | Inferred type from JavaScript expression analysis.
data InferredType
  = InfNumber        -- typeof === 'number'
  | InfString        -- typeof === 'string'
  | InfBoolean       -- typeof === 'boolean'
  | InfNull          -- null or undefined
  | InfArray InferredType  -- Array with inferred element type
  | InfObject [(Text, InferredType)]  -- Object with inferred fields
  | InfPromise InferredType  -- Promise/async
  | InfFunction [InferredType] InferredType
  | InfUnion [InferredType]  -- Union of possible types
  | InfUnknown       -- Cannot determine
  deriving (Eq, Show)

-- | Infer the type of a JavaScript expression.
inferExprType :: JSExpression -> InferredType
inferExprType = \case
  -- Literals
  JSDecimal _ _ -> InfNumber
  JSStringLiteral _ _ -> InfString
  JSHexInteger _ _ -> InfNumber
  JSOctal _ _ -> InfNumber
  JSLiteral _ "true" -> InfBoolean
  JSLiteral _ "false" -> InfBoolean
  JSLiteral _ "null" -> InfNull
  JSLiteral _ "undefined" -> InfNull

  -- Array literal: infer element types
  JSArrayLiteral _ elements _ ->
    inferArrayType (map inferExprType (extractElements elements))

  -- Object literal: infer field types
  JSObjectLiteral _ fields _ ->
    InfObject (map inferFieldType (extractFields fields))

  -- Binary operations
  JSExpressionBinary left op right ->
    inferBinaryOp (inferExprType left) op (inferExprType right)

  -- Ternary: union of both branches
  JSExpressionTernary cond _ thenExpr _ elseExpr ->
    InfUnion [inferExprType thenExpr, inferExprType elseExpr]

  -- Function call: infer from known functions
  JSMemberExpression obj _ member _ -> inferMemberCall obj member

  -- Unknown
  _ -> InfUnknown

-- | Detect mixed-type operations.
-- This is how we catch `1 + ""`.
inferBinaryOp :: InferredType -> JSBinOp -> InferredType -> InferredType
inferBinaryOp left op right =
  case op of
    JSBinOpPlus _ ->
      case (left, right) of
        (InfNumber, InfNumber) -> InfNumber
        (InfString, InfString) -> InfString
        (InfNumber, InfString) -> InfString  -- JS coerces: "1" + "" = "1"
          -- But this is a WARNING: mixed-type addition
        (InfString, InfNumber) -> InfString
          -- Also a WARNING
        _ -> InfUnknown
    JSBinOpMinus _ ->
      case (left, right) of
        (InfNumber, InfNumber) -> InfNumber
        _ -> InfNumber  -- JS coerces, but WARNING for non-numbers
    JSBinOpTimes _ -> InfNumber
    JSBinOpDivide _ -> InfNumber
    JSBinOpStrictEq _ -> InfBoolean
    JSBinOpStrictNeq _ -> InfBoolean
    JSBinOpLt _ -> InfBoolean
    JSBinOpGt _ -> InfBoolean
    JSBinOpAnd _ -> InfUnion [left, right]
    JSBinOpOr _ -> InfUnion [left, right]
    _ -> InfUnknown
```

### Step 4: Return Path Analysis

**File: `packages/canopy-core/src/FFI/StaticAnalysis/Returns.hs`** (new)

Analyze all possible return paths in a function:

```haskell
-- | Analyze all return paths of a JavaScript function.
-- Reports when:
-- 1. Some paths return a value and others don't (missing return)
-- 2. Return types are inconsistent across paths
-- 3. null/undefined can leak through non-Maybe return type
analyzeReturnPaths :: JSStatement -> [ReturnPath]
analyzeReturnPaths = go []
  where
    go paths = \case
      JSReturn _ (Just expr) _ ->
        ReturnPath (inferExprType expr) : paths
      JSReturn _ Nothing _ ->
        ReturnPath InfNull : paths  -- Implicit undefined return
      JSIf _ _ _ thenBlock _ (Just elseBlock) ->
        go (go paths thenBlock) elseBlock
      JSIf _ _ _ thenBlock _ Nothing ->
        ReturnPath InfNull : go paths thenBlock  -- Missing else = possible undefined
      JSTry _ tryBlock _ catchBlock _ ->
        go (go paths tryBlock) catchBlock
      JSStatementBlock _ stmts _ _ ->
        foldl' go paths stmts
      _ -> paths  -- Statement without explicit return = implicit undefined

-- | Check if function's return paths are consistent with @canopy-type.
checkReturnConsistency :: Text -> FFIType -> [ReturnPath] -> [FFIWarning]
checkReturnConsistency funcName declaredType paths =
  concatMap (checkOnePath funcName declaredType) paths

checkOnePath :: Text -> FFIType -> ReturnPath -> [FFIWarning]
checkOnePath funcName declared (ReturnPath inferred) =
  case (declared, inferred) of
    -- Declared non-Maybe but can return null
    (FFIInt, InfNull) ->
      [NullableReturnWithoutMaybe region funcName]
    (FFIString, InfNull) ->
      [NullableReturnWithoutMaybe region funcName]
    (FFIBool, InfNull) ->
      [NullableReturnWithoutMaybe region funcName]
    -- Declared Int but returns string
    (FFIInt, InfString) ->
      [TypeMismatch region funcName inferred declared]
    -- Declared Result but no $ tag
    (FFIResult _ _, InfObject fields) | not (hasTag fields) ->
      [ResultTagMissing region funcName]
    -- OK cases
    (FFIInt, InfNumber) -> []
    (FFIFloat, InfNumber) -> []
    (FFIString, InfString) -> []
    (FFIBool, InfBoolean) -> []
    (FFIMaybe _, InfNull) -> []  -- null is valid for Maybe
    (FFIMaybe inner, other) -> checkOnePath funcName inner (ReturnPath other)
    -- Unknown: can't verify, no warning
    (_, InfUnknown) -> []
    _ -> []

hasTag :: [(Text, InferredType)] -> Bool
hasTag fields = any (\(k, _) -> k == "$") fields
```

### Step 5: Mixed-Type Operation Detection

**File: `packages/canopy-core/src/FFI/StaticAnalysis/MixedOps.hs`** (new)

Detect the `1 + ""` class of errors:

```haskell
-- | Detect mixed-type operations in JavaScript expressions.
-- These are patterns where JavaScript's implicit coercion causes
-- unexpected behavior that violates Canopy's type expectations.
detectMixedOps :: JSStatement -> [FFIWarning]
detectMixedOps = walkExpressions checkExpr
  where
    checkExpr = \case
      JSExpressionBinary left (JSBinOpPlus _) right ->
        checkMixedAdd (inferExprType left) (inferExprType right)
      JSExpressionBinary left (JSBinOpMinus _) right ->
        checkNumericOp "subtraction" (inferExprType left) (inferExprType right)
      JSExpressionBinary left (JSBinOpTimes _) right ->
        checkNumericOp "multiplication" (inferExprType left) (inferExprType right)
      -- Loose equality (== instead of ===)
      JSExpressionBinary _ (JSBinOpEq _) _ ->
        [UnsafeCoercion region "==" "==="]
      JSExpressionBinary _ (JSBinOpNeq _) _ ->
        [UnsafeCoercion region "!=" "!=="]
      _ -> []

    checkMixedAdd InfNumber InfString =
      [MixedTypeOperation region "number" "string"]
    checkMixedAdd InfString InfNumber =
      [MixedTypeOperation region "string" "number"]
    checkMixedAdd InfNull InfNumber =
      [MixedTypeOperation region "null" "number"]
    checkMixedAdd InfNull InfString =
      [MixedTypeOperation region "null" "string"]
    checkMixedAdd _ _ = []

    checkNumericOp opName left right =
      case (left, right) of
        (InfString, _) -> [MixedTypeOperation region "string" opName]
        (_, InfString) -> [MixedTypeOperation region opName "string"]
        (InfNull, _) -> [MixedTypeOperation region "null" opName]
        (_, InfNull) -> [MixedTypeOperation region opName "null"]
        _ -> []
```

### Step 6: Integration Into Compilation Pipeline

**File: `packages/canopy-core/src/Canonicalize/Module/FFI.hs`**

Run static analysis during canonicalization (when FFI files are already parsed):

```haskell
canonicalizeFFI :: Env -> Src.FFI -> Result Can.FFI
canonicalizeFFI env ffi = do
  -- Existing: parse JSDoc, extract types
  jsAst <- parseJavaScriptFile (ffi ^. ffiPath)
  declaredTypes <- extractDeclaredTypes jsAst

  -- NEW: Static analysis of JavaScript code
  let analysis = StaticAnalysis.analyzeFFIFile (ffi ^. ffiPath) jsAst declaredTypes

  -- Report errors (block compilation)
  traverse_ reportFFIError (analysis ^. analysisErrors)

  -- Report warnings (don't block, but visible)
  traverse_ reportFFIWarning (analysis ^. analysisWarnings)

  -- Continue with canonicalization
  canonicalizeFFIBindings env declaredTypes jsAst
```

### Step 7: Error Reporting

**File: `packages/canopy-core/src/Reporting/Error/FFI.hs`** (new)

```haskell
-- | Format FFI analysis warnings with clear diagnostics.
--
-- Example output for mixed-type operation:
--
-- @
-- -- FFI TYPE WARNING - src/ffi/math.js:5:15
--
-- I found a mixed-type addition in the FFI function `calculate`:
--
--   5|  return count + name;
--               ^^^   ^^^^
--              number  string
--
-- JavaScript will coerce this to string concatenation, but the
-- function is declared as returning `Int`:
--
--   @canopy-type String -> Int -> Int
--
-- This will cause a runtime type error. Either:
--   1. Fix the JavaScript to only add numbers
--   2. Change the @canopy-type to return String
-- @
--
-- Example output for nullable return:
--
-- @
-- -- FFI TYPE WARNING - src/ffi/storage.js:12:5
--
-- The FFI function `getValue` can return `undefined`:
--
--   10|  function getValue(key) {
--   11|    const val = data[key];
--   12|    return val;  // val could be undefined!
--        ^^^^^^^^^
--
-- But it is declared as returning `String` (not `Maybe String`):
--
--   @canopy-type String -> String
--
-- If the key doesn't exist, `undefined` will leak into Canopy code.
-- Change the type to `String -> Maybe String` or add a null check:
--
--   return val !== undefined ? val : '';
-- @
formatFFIWarning :: FFIWarning -> Doc
```

---

## What This Catches (Outperforming Flow)

| Pattern | Flow | Canopy (After) | Example |
|---------|------|---------------|---------|
| `number + string` | Yes | **Yes** — at compile time in FFI JS | `return count + name` |
| `null + number` | Yes | **Yes** — detected as mixed op | `return x + null` |
| Nullable return without Maybe | Yes | **Yes** — return path analysis | `return data[key]` |
| Missing return branch | Yes | **Yes** — control flow analysis | `if (x) return 5;` (no else) |
| Wrong Result tag | No | **Yes** — Canopy-specific | `return value` instead of `{ $: 'Ok', a: value }` |
| `==` instead of `===` | Yes | **Yes** — unsafe coercion warning | `if (x == null)` |
| Promise for non-Task type | No | **Yes** — async/type mismatch | `async function` with `@canopy-type Int` |
| Array element type mismatch | Partial | **Yes** — element inference | `return [1, "two", 3]` for `List Int` |
| **Purity advantage** | No | **Yes** — Canopy values never change | Narrowing never invalidated |
| **Full inference in pure code** | No (requires annotations at boundaries) | **Yes** — HM infers everything | No annotations needed in Canopy code |

### Key Advantage Over Flow

Flow requires type annotations at module boundaries ("Types-First" architecture). Canopy's HM inference + FFI static analysis means:

1. **Zero annotations needed in Canopy code** — types are inferred
2. **JavaScript is analyzed statically** — catching issues before runtime
3. **Runtime validators catch anything static analysis misses** — defense in depth
4. **Purity means narrowing is never invalidated** — Flow must invalidate after function calls

---

## Testing

### Unit Tests

```haskell
testMixedTypeDetection :: TestTree
testMixedTypeDetection = testGroup "FFI Mixed-Type Detection"
  [ testCase "number + string detected" $ do
      let js = "function add(a, b) { return a + b; }"
          types = Map.singleton "add" (FFIFunctionType [FFIInt, FFIInt] FFIInt)
      warnings <- analyzeJS js types
      assertBool "should warn" (any isMixedTypeWarning warnings)

  , testCase "number + number ok" $ do
      let js = "function add(a, b) { return a + b; }"
          types = Map.singleton "add" (FFIFunctionType [FFIInt, FFIInt] FFIInt)
      warnings <- analyzeJS js types
      assertBool "no warnings for matching types" (null (filter isMixedTypeWarning warnings))

  , testCase "nullable return detected" $ do
      let js = "function get(k) { return data[k]; }"
          types = Map.singleton "get" (FFIFunctionType [FFIString] FFIString)
      warnings <- analyzeJS js types
      assertBool "should warn about null" (any isNullableWarning warnings)

  , testCase "missing return path detected" $ do
      let js = "function check(x) { if (x > 0) return x; }"
          types = Map.singleton "check" (FFIFunctionType [FFIInt] FFIInt)
      warnings <- analyzeJS js types
      assertBool "should warn about missing return" (any isMissingReturnWarning warnings)
  ]

testResultTagValidation :: TestTree
testResultTagValidation = testGroup "Result Tag Validation"
  [ testCase "missing $ tag detected" $ do
      let js = "function parse(s) { try { return JSON.parse(s); } catch(e) { return null; } }"
          types = Map.singleton "parse" (FFIFunctionType [FFIString] (FFIResult FFIString FFIInt))
      warnings <- analyzeJS js types
      assertBool "should detect missing Result tag" (any isResultTagWarning warnings)
  ]
```

### Integration Tests

```haskell
testEndToEndFFISafety :: TestTree
testEndToEndFFISafety = testGroup "E2E FFI Type Safety"
  [ testCase "compile with FFI warnings" $ do
      result <- compileProject "test/fixtures/ffi-mixed-types/"
      assertBool "should produce warnings" (hasFFIWarnings result)
      assertBool "should still compile" (isRight result)

  , testCase "strict mode catches runtime mismatch" $ do
      result <- runCompiledProject "test/fixtures/ffi-wrong-return/"
      assertBool "should throw runtime error" (hasRuntimeError result)
  ]
```

---

## Validation

```bash
make build
make test

# Run FFI-specific tests
stack test --ta="--pattern FFI"

# Test with real FFI projects
cd test/fixtures/ffi-examples && canopy make --ffi-strict
```

---

## Success Criteria

- [ ] `--ffi-strict` is the default (runtime validation always on)
- [ ] `--ffi-unsafe` is available as opt-in for performance
- [ ] Static analysis detects `number + string` in FFI JavaScript files
- [ ] Static analysis detects nullable returns for non-Maybe types
- [ ] Static analysis detects missing return paths
- [ ] Static analysis detects wrong Result tag construction
- [ ] Static analysis detects `==` vs `===` usage
- [ ] Static analysis detects async functions without Task type
- [ ] Warnings include exact line numbers and fix suggestions
- [ ] All existing FFI tests pass
- [ ] 50+ new tests for static analysis
- [ ] `make build` passes with zero warnings
- [ ] Runtime validation errors are clear and actionable
