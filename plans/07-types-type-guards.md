# Plan 07: Type Guards & Predicate Functions

**Priority**: HIGH
**Effort**: Medium (3-4 days)
**Risk**: Medium
**Audit Finding**: No user-defined type narrowing functions; Flow's `%checks` / `x is T` predicates are a key ergonomic advantage

---

## Problem

In Flow, users can write custom type guard functions:
```javascript
function isString(x: mixed): x is string { return typeof x === 'string'; }
```

After calling `isString(value)`, Flow narrows `value` to `string` in the truthy branch. This enables clean, reusable narrowing logic.

Canopy relies on pattern matching for narrowing, which works for constructors but not for arbitrary predicates. Users cannot write a function `isPositive : Int -> Bool` and have the type system narrow the `Int` to a positive range.

---

## Solution

Add **type-narrowing annotations** to Canopy functions. When a function is annotated as a type guard, the compiler narrows the argument type in `if` branches.

### Syntax

```elm
-- Type guard function: narrows first argument to the specified type
isOk : Result err ok -> ok guards Ok ok
isOk result =
  case result of
    Ok _ -> True
    Err _ -> False

-- Usage: automatic narrowing
handleResult : Result String Int -> Int
handleResult result =
  if isOk result then
    -- result is narrowed to Ok Int here
    unwrapOk result  -- safe, compiler knows it's Ok
  else
    0
```

### Alternative Simpler Syntax — Boolean Refinements

For Canopy's pure functional style, a simpler approach leverages the existing `case` system with a new `narrowing` keyword:

```elm
-- A narrowing function returns a Narrowed type
narrow : Maybe a -> Narrowed (Just a)
narrow maybeVal =
  case maybeVal of
    Just _ -> proven
    Nothing -> disproven

-- In an if-expression, the compiler tracks the narrowing
process : Maybe Int -> Int
process maybeVal =
  if narrow maybeVal then
    -- maybeVal is Known to be Just here
    fromJust maybeVal  -- safe, compiler-guaranteed
  else
    0
```

---

## Implementation

### Step 1: Add Guard Annotation to Type System

**File: `packages/canopy-core/src/AST/Source.hs`**

```haskell
-- | A function's type can include a guard annotation.
data TypeAnnotation = TypeAnnotation
  { _annType :: !Type_
  , _annGuard :: !(Maybe GuardAnnotation)
  }

-- | Specifies what type the first argument is narrowed to when the
-- function returns True.
data GuardAnnotation = GuardAnnotation
  { _guardArgIndex :: !Int  -- which argument is narrowed (0-based)
  , _guardNarrowType :: !Type_  -- what it's narrowed to
  }
```

### Step 2: Parse Guard Syntax

**File: `packages/canopy-core/src/Parse/Type.hs`**

```haskell
-- Parse: `isOk : Result err ok -> Bool guards Ok ok`
parseTypeAnnotation :: Parser TypeAnnotation
parseTypeAnnotation = do
  ty <- parseType
  guard <- optional parseGuardClause
  pure (TypeAnnotation ty guard)

parseGuardClause :: Parser GuardAnnotation
parseGuardClause = do
  Keyword.guards
  narrowType <- parseType
  pure (GuardAnnotation 0 narrowType)
```

### Step 3: Constraint Generation for Guards

**File: `packages/canopy-core/src/Type/Constrain/Expression.hs`**

When a guard function is used in an `if` condition:

```haskell
constrainIf :: Region -> Can.Expr -> Can.Expr -> Can.Expr -> Expected -> IO Constraint
constrainIf region condition thenBranch elseBranch expected = do
  case extractGuardCall condition of
    Just (guardFn, argExpr, narrowType) -> do
      -- In thenBranch: argExpr has narrowed type
      thenConstraint <- withNarrowedType argExpr narrowType $
        constrain thenBranch expected
      -- In elseBranch: argExpr has the complement type
      elseConstraint <- constrain elseBranch expected
      pure (CAnd [condConstraint, thenConstraint, elseConstraint])
    Nothing ->
      -- Normal if-expression
      normalIfConstraint region condition thenBranch elseBranch expected
```

### Step 4: Guard Verification

The compiler must verify that the guard function is consistent:
1. The return type must be `Bool`
2. The narrow type must be a valid refinement of the argument type
3. The function body must actually check for the narrowed constructor

**File: `packages/canopy-core/src/Type/Verify/Guard.hs`** (new)

```haskell
-- | Verify that a guard function's body is consistent with its annotation.
verifyGuard :: Can.Def -> GuardAnnotation -> Either GuardError ()
verifyGuard def guard = do
  -- Check 1: return type is Bool
  ensureReturnsBool (def ^. defType)
  -- Check 2: narrow type is a subtype of the parameter type
  ensureValidNarrowing (paramType def (guard ^. guardArgIndex)) (guard ^. guardNarrowType)
  -- Check 3: body contains a pattern match that distinguishes the cases
  ensureDiscriminating (def ^. defBody) (guard ^. guardNarrowType)
```

### Step 5: Error Reporting

**File: `packages/canopy-core/src/Reporting/Error/Type/Guard.hs`** (new)

```haskell
-- | Error for inconsistent guard function.
--
-- Example:
-- @
-- -- GUARD ERROR - src/Main.can:15:1
--
-- The function `isOk` is annotated as a type guard that narrows
-- its argument to `Ok a`, but the function body does not actually
-- check for this constructor:
--
--   15| isOk : Result err ok -> Bool guards Ok ok
--   16| isOk result = True  -- always returns True!
--
-- A guard function must contain a case expression that distinguishes
-- the narrowed type from other constructors.
-- @
```

---

## Examples

```elm
-- Example 1: Maybe guard
isJust : Maybe a -> Bool guards Just a
isJust m =
  case m of
    Just _ -> True
    Nothing -> False

-- Usage
safeHead : List a -> Maybe a -> a
safeHead fallback maybeVal =
  if isJust maybeVal then
    fromJust maybeVal  -- Safe: compiler knows it's Just
  else
    List.head fallback

-- Example 2: Result guard
isOk : Result err ok -> Bool guards Ok ok
isOk result =
  case result of
    Ok _ -> True
    Err _ -> False

-- Example 3: Custom type guard
type Shape
  = Circle Float
  | Rectangle Float Float
  | Triangle Float Float Float

isCircle : Shape -> Bool guards Circle Float
isCircle shape =
  case shape of
    Circle _ -> True
    _ -> False
```

---

## Validation

```bash
make build
make test
stack test --ta="--pattern Guard"
```

---

## Success Criteria

- [ ] `guards` keyword parses in type annotations
- [ ] Guard functions narrow argument types in `if` branches
- [ ] Compiler verifies guard consistency (body must check for the type)
- [ ] Invalid guards produce clear error messages
- [ ] 30+ tests for guard parsing, verification, and narrowing
- [ ] `make build` passes, `make test` passes
- [ ] No performance regression (< 2% on type checking)
