# Plan 08: Variance Annotations

**Priority**: MEDIUM
**Effort**: Medium (3-4 days)
**Risk**: Medium
**Audit Finding**: No explicit variance control; Flow's `+`/`-` annotations catch soundness bugs that implicit variance misses

---

## Problem

Flow allows explicit variance annotations on type parameters:
- `+T` (covariant): output-only, enables flexible subtyping
- `-T` (contravariant): input-only, reverses subtyping direction

TypeScript added `in`/`out` keywords later for the same purpose.

Canopy has no variance annotations. This means:
1. Library authors cannot express that a container is read-only (covariant)
2. No compile-time enforcement that mutable containers are invariant
3. Potential for unsound usage patterns in generic code

---

## Solution

Add optional variance annotations to type parameters using `+` (covariant/out) and `-` (contravariant/in):

```elm
-- Read-only container: covariant in a
type ReadList (+a) = List a

-- Write-only consumer: contravariant in a
type Consumer (-a) = a -> Cmd msg

-- Default (no annotation): invariant
type MutableRef a = { get : () -> a, set : a -> () }
```

---

## Implementation

### Step 1: Extend Type Parameter AST

**File: `packages/canopy-core/src/AST/Source.hs`**

```haskell
data Variance = Covariant | Contravariant | Invariant
  deriving (Eq, Show)

data TypeParam = TypeParam
  { _tpName :: !Name
  , _tpVariance :: !Variance
  }
```

### Step 2: Parse Variance Annotations

**File: `packages/canopy-core/src/Parse/Type.hs`**

```haskell
parseTypeParam :: Parser TypeParam
parseTypeParam = do
  variance <- parseVariance
  name <- parseTypeVarName
  pure (TypeParam name variance)

parseVariance :: Parser Variance
parseVariance =
  oneOf
    [ Covariant <$ Symbol.plus
    , Contravariant <$ Symbol.minus
    , pure Invariant
    ]
```

### Step 3: Variance Checking

**File: `packages/canopy-core/src/Type/Variance.hs`** (new)

After type checking, verify that the declared variance matches the actual usage:

```haskell
-- | Check that a type parameter's declared variance matches its usage.
-- A covariant (+a) parameter must only appear in positive positions.
-- A contravariant (-a) parameter must only appear in negative positions.
checkVariance :: Can.TypeAlias -> [TypeParam] -> Either VarianceError ()
checkVariance alias params =
  traverse_ (checkParamVariance alias) params

checkParamVariance :: Can.TypeAlias -> TypeParam -> Either VarianceError ()
checkParamVariance alias param = do
  positions <- collectPositions (param ^. tpName) (alias ^. aliasBody)
  case param ^. tpVariance of
    Covariant ->
      when (any isNegative positions) $
        Left (CovariantInNegativePosition param positions)
    Contravariant ->
      when (any isPositive positions) $
        Left (ContravariantInPositivePosition param positions)
    Invariant ->
      pure ()  -- No checking needed for invariant

-- | Track whether a type variable appears in positive or negative position.
-- Positive = return types, record fields (output)
-- Negative = function parameters (input)
-- Both = invariant usage
data Position = Positive | Negative | Both

collectPositions :: Name -> Can.Type -> [Position]
collectPositions name = go Positive
  where
    go polarity = \case
      Can.TVar n | n == name -> [polarity]
      Can.TLambda arg ret ->
        go (flipPolarity polarity) arg ++ go polarity ret
      Can.TRecord fields _ ->
        concatMap (go polarity . snd) fields
      Can.TAlias _ _ args _ ->
        concatMap (go polarity . snd) args
      Can.TType _ _ args ->
        concatMap (go polarity) args
      _ -> []

flipPolarity :: Position -> Position
flipPolarity Positive = Negative
flipPolarity Negative = Positive
flipPolarity Both = Both
```

### Step 4: Subtyping with Variance

When two types with variance annotations are compared:

```haskell
-- | Check subtyping relationship considering variance.
-- ReadList Animal <: ReadList Cat -- YES (covariant, Cat <: Animal → ReadList Cat <: ReadList Animal)
-- Consumer Animal <: Consumer Cat -- NO (contravariant, reversed)
checkSubtype :: Type -> Type -> Bool
checkSubtype (TApp con1 args1) (TApp con2 args2)
  | con1 == con2 = all checkArgSubtype (zip3 (variances con1) args1 args2)
  where
    checkArgSubtype (Covariant, sub, super) = checkSubtype sub super
    checkArgSubtype (Contravariant, sub, super) = checkSubtype super sub  -- flipped
    checkArgSubtype (Invariant, sub, super) = sub == super  -- exact match
```

### Step 5: Error Reporting

```haskell
-- Example error:
-- @
-- -- VARIANCE ERROR - src/Container.can:5:12
--
-- The type parameter `a` is declared covariant (+a) but appears
-- in a contravariant (input) position:
--
--   5| type MyList (+a) = { items : List a, add : a -> MyList a }
--                                                     ^
-- The `add` function takes `a` as input, which requires invariant
-- or contravariant variance.
--
-- Hint: Remove the `+` to make `a` invariant, or remove the `add`
-- field to keep it covariant.
-- @
```

---

## Examples

```elm
-- Covariant: read-only access
type alias ReadonlyList (+a) =
  { items : List a
  , length : Int
  , get : Int -> Maybe a
  }

-- This is safe because ReadonlyList is covariant:
-- ReadonlyList Cat can be used where ReadonlyList Animal is expected

-- Contravariant: write-only access
type alias Sink (-a) =
  { write : a -> Cmd msg
  , close : Cmd msg
  }

-- Sink Animal can be used where Sink Cat is expected
-- (if you can write any Animal, you can certainly write a Cat)

-- Invariant (default): both read and write
type alias MutableBox a =
  { get : () -> a
  , set : a -> ()
  }
-- MutableBox Cat cannot be used as MutableBox Animal (unsafe read)
-- MutableBox Animal cannot be used as MutableBox Cat (unsafe write)
```

---

## Validation

```bash
make build
make test
stack test --ta="--pattern Variance"
```

---

## Success Criteria

- [ ] `+a` and `-a` syntax parses in type parameter lists
- [ ] Variance violations produce clear error messages
- [ ] Covariant parameters cannot appear in negative positions
- [ ] Contravariant parameters cannot appear in positive positions
- [ ] Subtyping respects declared variance
- [ ] 25+ tests covering all variance scenarios
- [ ] `make build` passes, `make test` passes
