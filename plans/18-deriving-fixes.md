# Plan 18: Deriving System — Bug Fixes and Completion

## Context

The deriving system (Plan 17) has a working foundation for enums and record aliases, but deep testing reveals 5 critical issues: union constructor arguments are silently dropped, parametric types crash the compiler, no validation rejects invalid types, no user-facing error messages exist, and Show for non-enum unions falls back to Debug.toString.

## Bugs to Fix (Priority Order)

### Bug 1: Union constructor arguments silently dropped in JSON encode/decode

**Severity**: Critical — silent data loss

**Root Cause**: `Optimize/Derive.hs` lines 238-242 and 319-322. The `if numArgs == 0 then ... else ...` branches produce identical code. Only the tag is encoded; constructor arguments are never serialized.

**Current behavior**:
- `encodeShape (Circle 3.14)` → `{}` (empty object, argument lost)
- `encodeShape (Rectangle 2.0 3.0)` → `{}` (both arguments lost)

**Expected behavior**:
- `encodeShape (Circle 3.14)` → `{"tag":"Circle","contents":3.14}`
- `encodeShape (Rectangle 2.0 3.0)` → `{"tag":"Rectangle","contents":[2.0,3.0]}`
- `encodeShape Point` → `{"tag":"Point"}`

**JS Runtime Representation** (from research):
- `Circle 3.14` → `{ $: 'Circle', 0: 3.14 }` (dev mode)
- `Rectangle 2.0 3.0` → `{ $: 'Rectangle', 0: 2.0, 1: 3.0 }`
- `Point` → `{ $: 'Point' }` (dev mode, or just integer for Enum)
- Constructor arg fields use `JsName.fromIndex` for names (0, 1, 2, ...)

**Fix in `Optimize/Derive.hs`**:

#### Encode (taggedEncodeBranch, lines 229-242)

Replace the current function. For each constructor:
- Access the `$` field to match the constructor tag
- For 0-arg: emit `{"tag": "CtorName"}`
- For 1-arg: emit `{"tag": "CtorName", "contents": encodedArg}`
- For N-arg: emit `{"tag": "CtorName", "contents": [encodedArg0, encodedArg1, ...]}`

To encode the arguments, we need to access them from the value. The value is a JS object like `{$: "Circle", 0: 3.14}`. We access field at `Index.ZeroBased i` using `Opt.Index`. However, at the Opt level, the arguments are accessed differently.

**Key insight**: At the `Opt.Expr` level, we need to use accessor patterns. Looking at how case expressions work, the pattern match destructuring accesses constructor args positionally. For the encoder, we need:
1. Access the value's positional fields (these correspond to `Can.Ctor`'s arg types)
2. For each arg, call the appropriate encoder (using `Port.toEncoder` or a recursive call)
3. Wrap in the tagged object format

**Implementation approach**:
```haskell
taggedEncodeBranch :: ModuleName.Canonical -> Opt.Expr -> Opt.Expr -> Can.Ctor -> Names.Tracker (Opt.Expr, Opt.Expr)
taggedEncodeBranch home encodeObject encodeString (Can.Ctor ctorName index numArgs argTypes) =
  do
    let dollar = Name.fromChars "$"
    cond <- kernelEq (Opt.Access (Opt.VarLocal dollar) (Name.fromChars "$")) (Opt.VarEnum (Opt.Global home ctorName) index)
    let tagPair = Opt.Tuple (Opt.Str (Name.toCanopyString (Name.fromChars "tag"))) (Opt.Call encodeString [Opt.Str (Name.toCanopyString ctorName)]) Nothing
    case numArgs of
      0 ->
        pure (cond, Opt.Call encodeObject [Opt.List [tagPair]])
      1 ->
        do
          -- Access field 0 of the value, encode it
          -- argTypes is [(Can.Type)] from the Ctor
          encoder <- toEncoderForType (head argTypes)
          let argExpr = Opt.Access (Opt.VarLocal dollar) (indexToFieldName 0)
          let contentsPair = Opt.Tuple (Opt.Str contentsStr) (Opt.Call encoder [argExpr]) Nothing
          pure (cond, Opt.Call encodeObject [Opt.List [tagPair, contentsPair]])
      _ ->
        do
          -- Multiple args: encode as array in "contents"
          encodedArgs <- zipWithM (\i typ -> do
            enc <- toEncoderForType typ
            let argExpr = Opt.Access (Opt.VarLocal dollar) (indexToFieldName i)
            pure (Opt.Call enc [argExpr])
            ) [0..] argTypes
          encodeList <- Names.registerGlobal elmJsonEncode "list"
          identity <- Names.registerGlobal elmJsonEncode "identity"  -- or build a JS array
          let contentsPair = Opt.Tuple (Opt.Str contentsStr) (Opt.Call encodeList [identity, Opt.List encodedArgs]) Nothing
          pure (cond, Opt.Call encodeObject [Opt.List [tagPair, contentsPair]])
```

**Challenge**: We need access to `Can.Ctor`'s argument types (`[Can.Type]`) to call the right encoder per arg. Currently `Can.Ctor` is `Ctor Name Index.ZeroBased Int [Can.Type]` — the 4th field is the arg types. We need to pass these through.

**Challenge 2**: Accessing constructor fields by index. At the Opt.Expr level, we need to produce `value.a` or `value.b` etc. (the minified field names from `JsName.fromIndex`). In the AST, this is done via `Opt.Access expr fieldName` where fieldName matches what `JsName.fromIndex` produces. We need a helper:

```haskell
indexToFieldName :: Int -> Name.Name
indexToFieldName i = Name.fromChars (Name.toChars (intToAscii i))
```

But `intToAscii` is in `Generate.JavaScript.Name` — it's a JS codegen concern, not an Opt-level concern. At the Opt level, case expressions use `Opt.Index` paths which are translated at codegen time. We need a different approach.

**Better approach**: Use `Opt.Index` from `AST/Optimized.hs`. Look at how `Opt.Destruct` works — destructuring a case match uses `Opt.Path` with `Opt.Index`. But these are for pattern matching, not for building encoder expressions.

**Simplest correct approach**: At the Opt.Expr level, the JS codegen for `Opt.Access expr name` produces `expr.name`. For constructor fields in dev mode, the fields are literally named `"0"`, `"1"`, etc. So we can use:

```haskell
Opt.Access (Opt.VarLocal dollar) (Name.fromChars (show i))
```

Wait — that won't work because `Name.fromChars "0"` doesn't produce a valid JS identifier. Looking at Expression.hs generateCtor (line 338), the field names come from `JsName.fromIndex` which calls `JsName.fromInt` which calls `intToAscii`. For index 0, that produces `"a"`. For index 1, `"b"`. Etc.

**So**: Constructor arg 0 is field `"a"`, arg 1 is field `"b"`, arg 2 is field `"c"`, etc. These are `Name.Name` values. We need:

```haskell
-- Convert a 0-based index to the field name used by JS codegen
ctorArgFieldName :: Int -> Name.Name
ctorArgFieldName n
  | n < 26    = Name.fromChars [toEnum (fromEnum 'a' + n)]
  | otherwise = -- handle larger indices if needed
```

Actually, looking more carefully at `intToAscii` in `Generate/JavaScript/Name.hs`, index 0 maps to byte 97 (`a`), index 1 to 98 (`b`), etc. So for constructor args, the field names at the Opt level should match.

But wait — at the Opt.Expr level, field access uses `Name.Name` which then gets converted to a `JsName.Name` at codegen. The `Opt.Access` is designed for record field access (`.fieldName`). For constructor fields, the case expression machinery uses `Opt.Destruct` with index paths. We need to make `Opt.Access` work with the same names.

**Validation step**: Let's check what `Opt.Access` generates. In `Generate/JavaScript/Expression.hs`, `Opt.Access expr name` generates `expr.name` where name goes through `JsName.fromLocal`. So `Opt.Access val (Name.fromChars "a")` would generate `val.a` in JS. And constructor field 0 IS `a` in the generated JS. This should work.

**Final approach for field access**:
```haskell
ctorArgFieldName :: Int -> Name.Name
ctorArgFieldName i
  | i < 26    = Name.fromChars [toEnum (fromEnum 'a' + i)]
  | otherwise = Name.fromChars [toEnum (fromEnum 'A' + i - 26)]
```

This matches `intToAscii` for the first 52 positions, which covers any realistic constructor arity.

#### Decode (taggedDecodeBranch, lines 312-322)

For decoding, we need to:
- 0-arg: `succeed CtorName`
- 1-arg: `field "contents" (map CtorName decoder0)`
- N-arg: chain `index 0 decoder0`, `index 1 decoder1` inside an andThen on the "contents" field

```haskell
taggedDecodeBranch :: ModuleName.Canonical -> Opt.Expr -> Can.Ctor -> Names.Tracker (Opt.Expr, Opt.Expr)
taggedDecodeBranch home succeed (Can.Ctor ctorName _ numArgs argTypes) =
  case numArgs of
    0 ->
      -- succeed CtorName
      pure (cond, Opt.Call succeed [ctorVal])
    1 ->
      do
        -- field "contents" (map CtorName decoder0)
        decodeField <- Names.registerGlobal elmJsonDecode "field"
        decodeMap <- Names.registerGlobal elmJsonDecode "map"
        decoder0 <- toDecoderForType (head argTypes)
        let mapped = Opt.Call decodeMap [ctorVal, decoder0]
        pure (cond, Opt.Call decodeField [Opt.Str contentsStr, mapped])
    _ ->
      do
        -- Decode N args from "contents" array using index
        decodeField <- Names.registerGlobal elmJsonDecode "field"
        decodeIndex <- Names.registerGlobal elmJsonDecode "index"
        andThen <- Names.registerGlobal elmJsonDecode "andThen"
        -- Build: field "contents" (index 0 dec0 |> andThen (\a -> index 1 dec1 |> andThen (\b -> succeed (Ctor a b))))
        -- ... chain of andThen calls
```

**Helper needed**: A function that takes a `Can.Type` and returns the right encoder/decoder expression. For built-in types, this is straightforward (reuse Port.hs). For custom types that also derive, we need to reference their generated functions.

**For now**: Use `Port.toEncoder` / `Port.toDecoder` for the arg types. This works for all primitive and built-in types (Int, Float, Bool, String, Maybe, List, etc.). Custom nested types in union args (like `Node (Tree a)`) are a future extension.

### Bug 2: Validation and Error Messages

**Severity**: Critical — compiler crashes on invalid input instead of showing errors

**Root Cause**: `Canonicalize/Environment/Local.hs` lines 307-313 convert deriving clauses without any validation. No error constructors exist for deriving.

**Current behavior**: Function types, Dict, Set, Task, Cmd, Sub, type variables all pass through canonicalization silently, then crash at optimization with `InternalError.report`.

**Fix — 3 files**:

#### 2a. Add error types (`Reporting/Error/Canonicalize.hs`)

Add after the existing error constructors (around line 103):

```haskell
  | DerivingInvalid Ann.Region Name.Name DerivingTarget DerivingProblem
```

With supporting types:

```haskell
data DerivingTarget
  = DeriveTargetShow
  | DeriveTargetParse
  | DeriveTargetOrd
  | DeriveTargetJsonEncode
  | DeriveTargetJsonDecode

data DerivingProblem
  = DeriveFunctionType Can.Type
  | DeriveTypeVariable Name.Name
  | DeriveExtendedRecord
  | DeriveUnsupportedType Name.Name
```

This mirrors the existing `InvalidPayload` / `PortProblem` pattern used for ports (lines 129-143).

#### 2b. Add validation (`Canonicalize/Environment/Local.hs`)

Add a validation function modeled on `Canonicalize/Effects.hs` `checkPayload` (lines 194-233):

```haskell
checkDerivable :: Can.Type -> Either (Can.Type, Error.DerivingProblem) ()
checkDerivable tipe =
  case tipe of
    Can.TAlias _ _ args aliasedType ->
      checkDerivable (Type.dealias args aliasedType)
    Can.TLambda _ _ ->
      Left (tipe, Error.DeriveFunctionType tipe)
    Can.TVar name ->
      Left (tipe, Error.DeriveTypeVariable name)
    Can.TRecord _ (Just _) ->
      Left (tipe, Error.DeriveExtendedRecord)
    Can.TRecord fields Nothing ->
      traverse_ (checkDerivable . Can.fieldType) fields
    Can.TUnit -> Right ()
    Can.TTuple a b mc ->
      checkDerivable a >> checkDerivable b >> traverse_ checkDerivable mc
    Can.TType _home name args ->
      case args of
        [] | isBuiltinScalar name -> Right ()
        [arg] | isBuiltinContainer name -> checkDerivable arg
        _ -> Left (tipe, Error.DeriveUnsupportedType name)
```

Call this in `canonicalizeAlias` and `canonicalizeUnion` — for each deriving clause that requires serializable types (Json.Encode, Json.Decode, Show, Parse), validate the type body. For `DeriveOrd`, additionally check that all fields are `comparable`.

Integrate into the existing code at lines 283 and 346:

```haskell
-- After: let canDeriving = fmap canonicalizeDerivingClause srcDeriving
-- Add validation for each clause that needs it:
traverse_ (validateDerivingClause region name ctipe) canDeriving
```

Where:
```haskell
validateDerivingClause :: Ann.Region -> Name.Name -> Can.Type -> Can.DerivingClause -> Result i w ()
validateDerivingClause region typeName tipe clause =
  case clause of
    Can.DeriveOrd -> checkOrdDerivable region typeName tipe
    Can.DeriveShow -> checkShowDerivable region typeName tipe
    Can.DeriveJsonEncode _ -> checkJsonDerivable region typeName tipe DeriveTargetJsonEncode
    Can.DeriveJsonDecode _ -> checkJsonDerivable region typeName tipe DeriveTargetJsonDecode
    _ -> Result.ok ()
```

#### 2c. Add error rendering (`Reporting/Error/Canonicalize.hs` or `Diagnostics/Extended.hs`)

Add a case to `toDiagnostic`:

```haskell
DerivingInvalid region typeName target problem ->
  Diags.derivingInvalidDiagnostic source region typeName target problem
```

And the diagnostic builder:

```haskell
derivingInvalidDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> DerivingTarget -> DerivingProblem -> Diagnostic
```

Producing messages like:

```
-- DERIVING ERROR ---- src/Models.can

Cannot derive `Json.Encode` for type `Handler`:

    10| type alias Handler =
    11|     { name : String
    12|     , callback : String -> Msg
                         ^^^^^^^^^^^^^^
    13|     }
    14|     deriving (Json.Encode)

The field `callback` has type `String -> Msg` which is a function.

Functions cannot be serialized to JSON.

Hint: Remove the function field from the record, or remove `Json.Encode`
from the deriving clause and write a custom encoder.
```

### Bug 3: Parametric type aliases crash the compiler

**Severity**: High — compiler crash on valid-looking code

**Root Cause**: `Type/Constrain/Module.hs` line 236 passes `Map.empty` to `Instantiate.fromSrcType`. Any `Can.TVar` in the alias body triggers an InternalError.

**Current behavior**: `type alias Wrapper a = { value : a } deriving (Json.Encode)` → INTERNAL COMPILER ERROR

**Fix in `Type/Constrain/Module.hs`**:

The fix follows the exact pattern used by `letPort` (lines 71-85) and `constrainAnnotatedDef`:

```haskell
derivedAliasBindings ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  IO [(Name.Name, Type)]
derivedAliasBindings home typeName (Can.Alias typeParams _variances canType _bound clauses) =
  do
    -- Create rigid type variables for each type parameter (same as letPort pattern)
    rigidVars <- traverse (\name -> do { v <- nameToRigid name; return (name, v) }) typeParams
    let freeVarsMap = Map.fromList [(name, VarN var) | (name, var) <- rigidVars]

    -- Instantiate the alias body with the parameter bindings
    expandedType <- Instantiate.fromSrcType freeVarsMap canType

    -- Build selfType with type parameters included
    let typeArgs = [(name, VarN var) | (name, var) <- rigidVars]
    let selfType = AliasN home typeName typeArgs expandedType

    return (foldl (addDerivedBinding selfType typeName) [] clauses)
```

**For the generated function types**, `addDerivedBinding` already works correctly because `selfType` now includes the type variables. The type checker will infer:
- `encodeWrapper : Wrapper a -> Json.Encode.Value` (where `a` stays polymorphic)

**But this is incomplete**: For parametric types, the generated encoder/decoder for the inner `a` needs to be passed as an argument. For example:
- `encodeWrapper : (a -> Value) -> Wrapper a -> Value`
- `wrapperDecoder : Decoder a -> Decoder (Wrapper a)`

This requires changes to both `addDerivedBinding` (to add the extra function parameters to the type) and `Optimize/Derive.hs` (to accept and use the encoder/decoder functions at runtime).

**Phase 1 (this plan)**: Fix the crash. Accept parametric types but DON'T add the extra function parameters yet. The generated `encodeWrapper` will work for concrete instantiations (e.g., `encodeWrapper : Wrapper Int -> Value` when called with a `Wrapper Int`). The Port.hs encoder handles concrete types fine since it dealias-es through the alias to the record body.

**Phase 2 (future)**: Add explicit function parameters for type variables.

### Bug 4: Show for union types with arguments uses Debug.toString

**Severity**: Medium — produces correct-ish output but not the expected format

**Root Cause**: `Optimize/Derive.hs` lines 144-152. `toShowCtorExpr` ignores `_home` and `_alts`, delegates everything to `Debug.toString`.

**Current behavior**: `showShape (Rectangle 2.0 3.0)` → `Rectangle 3 2` (Debug.toString format, args reversed, decimals lost)

**Expected behavior**: `showShape (Rectangle 2.0 3.0)` → `Rectangle 2.0 3.0`

**Fix in `Optimize/Derive.hs`**:

Replace `toShowCtorExpr` to build if-chains similar to `toShowEnumExpr`, but for each constructor:
- Match on the `$` field (constructor tag)
- For 0-arg constructors: return just the constructor name
- For N-arg constructors: concatenate the constructor name with stringified arguments

```haskell
toShowCtorExpr :: ModuleName.Canonical -> [Can.Ctor] -> Names.Tracker Opt.Expr
toShowCtorExpr home alts =
  do
    let dollar = Name.fromChars "$"
    branches <- traverse (ctorShowBranch home) alts
    debugToString <- Names.registerGlobal ModuleName.debug "toString"
    let fallback = Opt.Call debugToString [Opt.VarLocal dollar]
    pure (Opt.Function [dollar] (buildIfChain branches fallback))

ctorShowBranch :: ModuleName.Canonical -> Can.Ctor -> Names.Tracker (Opt.Expr, Opt.Expr)
ctorShowBranch home (Can.Ctor ctorName index numArgs _argTypes) =
  do
    let dollar = Name.fromChars "$"
    cond <- kernelEq (Opt.Access (Opt.VarLocal dollar) (Name.fromChars "$"))
                     (Opt.VarEnum (Opt.Global home ctorName) index)
    let nameStr = Opt.Str (Name.toCanopyString ctorName)
    case numArgs of
      0 -> pure (cond, nameStr)
      _ ->
        do
          -- For each arg, call Debug.toString and concatenate with spaces
          debugToString <- Names.registerGlobal ModuleName.debug "toString"
          let argExprs = [Opt.Call debugToString [Opt.Access (Opt.VarLocal dollar) (ctorArgFieldName i)]
                         | i <- [0..numArgs-1]]
          let withSpaces = foldl (\acc arg -> Opt.Binop Opt.OpAppend acc (Opt.Binop Opt.OpAppend (Opt.Str spaceStr) arg)) nameStr argExprs
          pure (cond, withSpaces)
```

For the initial implementation, using `Debug.toString` per-arg is acceptable. A future improvement would use type-specific show functions (e.g., `String.fromFloat` for Float, `String.fromInt` for Int, etc.), but that requires threading the arg types through and matching them to the right conversion function.

**Note on string ops**: `Opt.Binop` may not have `OpAppend`. Check what the `++` operator compiles to. If it's a kernel call, use that instead. The simplest approach may be to use a kernel string append:

```haskell
strAppend <- Names.registerKernel Name.utils (Opt.VarKernel Name.utils (Name.fromChars "ap"))
```

Or build using `Opt.Str` concatenation if the optimizer supports it.

### Bug 5: Parse generation not implemented

**Severity**: Low — `DeriveParse` is accepted by parser but generates nothing

**Current behavior**: `deriving (Parse)` is parsed and stored but `addUnionClause`/`addAliasClause` returns `graph` unchanged for `Can.DeriveParse`.

**Fix**: This is a larger feature (Plan Step 6 from original plan). Defer to a separate plan. For now, add validation that produces a clear error:

```
-- NOT YET SUPPORTED ---- src/Models.can

    deriving (Parse) is not yet implemented.

    7| type Color = Red | Green | Blue
    8|     deriving (Parse)
                     ^^^^^

Hint: Parse deriving is planned for a future release.
For now, write a manual parser function.
```

## Implementation Order

### Step 1: Validation and Error Messages (Bug 2)

Do this FIRST because it prevents crashes on invalid input and provides the foundation for all other fixes.

Files:
- `Reporting/Error/Canonicalize.hs` — add `DerivingInvalid` error + subtypes
- `Reporting/Error/Canonicalize/Diagnostics/Extended.hs` — add diagnostic builder
- `Canonicalize/Environment/Local.hs` — add validation in `canonicalizeAlias` and `canonicalizeUnion`
- Binary serialization if errors are serialized

### Step 2: Union constructor args in JSON (Bug 1)

Files:
- `Optimize/Derive.hs` — rewrite `taggedEncodeBranch` and `taggedDecodeBranch`
- Need helper: `ctorArgFieldName :: Int -> Name.Name` to match JS codegen field names
- Need helper: `toEncoderForType` / `toDecoderForType` wrapping Port.hs for each arg type

### Step 3: Show for union args (Bug 4)

Files:
- `Optimize/Derive.hs` — rewrite `toShowCtorExpr` to produce per-constructor if-chains with arg stringification

### Step 4: Parametric type aliases (Bug 3)

Files:
- `Type/Constrain/Module.hs` — fix `derivedAliasBindings` to create rigid type variables from `Can.Alias` type params

### Step 5: Parse not-yet-implemented message (Bug 5)

Files:
- `Canonicalize/Environment/Local.hs` — emit a clear "not yet supported" error for `DeriveParse`

## Verification

For each step:

1. `stack build` — compiles without warnings
2. `make test` — all 3690 tests pass
3. End-to-end tests in `/tmp/test-deriving-edge/`:

| Test | Expected After Fix |
|------|-------------------|
| Nested record encode | `{"address":{"city":"Springfield","street":"123 Main"},"name":"Alice"}` |
| Maybe field encode | `{"name":"Alice","nickname":"Ali"}` / `{"name":"Bob","nickname":null}` |
| List field encode | `{"members":["Alice","Bob"],"name":"A-Team"}` |
| List (Maybe Int) encode | `{"data":[1,null,3]}` |
| Function type in record + Json.Encode | **Compile error** with clear message |
| Union with args encode (Circle 3.14) | `{"tag":"Circle","contents":3.14}` |
| Union with args encode (Rectangle 2 3) | `{"tag":"Rectangle","contents":[2.0,3.0]}` |
| Union with args decode roundtrip | `decode (encode (Circle 3.14)) == Ok (Circle 3.14)` |
| Show union with args | `showShape (Circle 3.14) == "Circle 3.14"` |
| Show union with args | `showShape (Rectangle 2.0 3.0) == "Rectangle 2.0 3.0"` |
| Parametric type alias | Compiles without crash |
| Record >8 fields decode | Works (already passing) |
| deriving (Parse) | Clear "not yet supported" error |
| Dict field + Json.Encode | **Compile error** with clear message |

## Files Modified (Summary)

| File | Change |
|------|--------|
| `Reporting/Error/Canonicalize.hs` | Add `DerivingInvalid` error constructor and subtypes |
| `Reporting/Error/Canonicalize/Diagnostics/Extended.hs` | Add diagnostic builder for deriving errors |
| `Canonicalize/Environment/Local.hs` | Add `checkDerivable` validation, call it during canonicalization |
| `Optimize/Derive.hs` | Rewrite `taggedEncodeBranch`, `taggedDecodeBranch`, `toShowCtorExpr`; add `ctorArgFieldName` helper |
| `Type/Constrain/Module.hs` | Fix `derivedAliasBindings` to handle type parameters |
| `AST/Canonical/Binary.hs` | Add serialization for new error types (if needed) |
