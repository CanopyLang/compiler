# Plan 07: Occurs Check Alias Body

**Priority:** CRITICAL
**Effort:** Small (2-4h)
**Risk:** Low -- the fix is a one-line addition with clear semantics

## Problem

The occurs check in `Type.Occurs.occursContent` does not traverse the `realVar`
(4th field) of the `Alias` constructor.  This means an infinite type hidden
behind an alias body is never detected, allowing the type checker to silently
accept programs that should be rejected as infinite-type errors.

### Root Cause

The `Alias` constructor in `Type.Type.Content` (line 120) carries four fields:

```haskell
-- /home/quinten/fh/canopy/packages/canopy-core/src/Type/Type.hs:120
Alias ModuleName.Canonical Name.Name [(Name.Name, Variable)] Variable
--    ^home                ^name      ^args                   ^realVar
```

The `realVar` is the underlying type that the alias expands to.  For example,
if `type Foo a = List a`, then `args = [("a", aVar)]` and
`realVar = Structure (App1 List [aVar])`.  The `realVar` can itself contain
any type structure, including references back to the variable being checked.

In `Type.Occurs` (line 55-56), the `Alias` case only traverses `args`:

```haskell
-- /home/quinten/fh/canopy/packages/canopy-core/src/Type/Occurs.hs:55-56
occursContent seen (Alias _ _ args _) foundCycle =
  foldrM (occursHelp seen) foundCycle (fmap snd args)
```

The wildcard `_` on the 4th field discards `realVar` entirely.

### Impact

If a unification step creates a cycle through an alias body -- e.g. a type
variable `v` gets unified such that `v = Alias ... [("a", v)] (Structure (Fun1 v ...))` --
the occurs check returns `False`, the solver does not emit an `InfiniteType`
error, and subsequent compilation stages (code generation, optimization) receive
a cyclic graph that can cause:

1. Non-termination in code generation traversals
2. Stack overflow during optimization passes
3. Silently incorrect generated code

### Related Skips in Other Functions

Two other traversals in the codebase also skip `realVar` in the `Alias` case:

1. **`Type.Type.getVarNames`** (line 562-563): Only traverses `args`, not `realVar`.
   This is intentional -- `getVarNames` collects user-visible variable names for
   error messages, and `realVar` does not introduce new names beyond those in `args`.

2. **`Type.Solve.Pool.adjustRankAlias`** (line 451-453): Only adjusts ranks for
   `args`, not `realVar`.  This appears to also be a bug with the same root cause,
   but the rank adjustment is a secondary concern compared to soundness.

In contrast, `Type.Solve.generalizeRecursively` (line 185-188) correctly handles
both `args` and `realVar`:

```haskell
-- /home/quinten/fh/canopy/packages/canopy-core/src/Type/Solve.hs:185-188
Alias _ _ args realVar -> do
  UF.set var (Descriptor content noRank mark copy)
  traverse_ (generalizeRecursively . snd) args
  generalizeRecursively realVar
```

This confirms that `realVar` must be traversed for correctness.

### All Callers of `Occurs.occurs`

| Call Site | File:Line | Context |
|-----------|-----------|---------|
| `Type.Unify.guardedUnify` | `Type/Unify.hs:140-141` | Pre-unification cycle check |
| `Type.Unify.comparableOccursCheck` | `Type/Unify.hs:392` | Comparable tuple cycle check |
| `Type.Solve.occurs` | `Type/Solve.hs:645` | Post-let-binding infinite type check |
| Tests | `test/Unit/Type/OccursTest.hs` | Various unit tests |

All callers rely on `Occurs.occurs` returning `True` when a cycle exists.  The
bug affects all four call sites identically.

## Files to Modify

### 1. `packages/canopy-core/src/Type/Occurs.hs` (line 55-56)

**Current code:**

```haskell
occursContent seen (Alias _ _ args _) foundCycle =
  foldrM (occursHelp seen) foundCycle (fmap snd args)
```

**Proposed change:**

```haskell
occursContent seen (Alias _ _ args realVar) foundCycle =
  foldrM (occursHelp seen) foundCycle (fmap snd args)
    >>= occursHelp seen realVar
```

This mirrors the pattern used by `occursTerm` for `Fun1` (line 65-66):

```haskell
Fun1 a b ->
  occursHelp seen b foundCycle >>= occursHelp seen a
```

The `realVar` is checked after `args` so that any cycle through either the
alias arguments or the alias body is detected.

### 2. `packages/canopy-core/src/Type/Solve/Pool.hs` (line 426, 451-453)

**Current code:**

```haskell
-- line 426
Alias _ _ args _ -> adjustRankAlias go args

-- lines 451-453
adjustRankAlias :: (Variable -> IO Int) -> [(Name.Name, Variable)] -> IO Int
adjustRankAlias go args =
  foldM (\rank (_, argVar) -> max rank <$> go argVar) outermostRank args
```

**Proposed change:**

```haskell
-- line 426
Alias _ _ args realVar -> adjustRankAlias go args realVar

-- updated signature and implementation
adjustRankAlias :: (Variable -> IO Int) -> [(Name.Name, Variable)] -> Variable -> IO Int
adjustRankAlias go args realVar = do
  argsRank <- foldM (\rank (_, argVar) -> max rank <$> go argVar) outermostRank args
  realRank <- go realVar
  return (max argsRank realRank)
```

This ensures that the rank of the underlying type body is also considered
during generalization rank adjustment.

### 3. `test/Unit/Type/OccursTest.hs` -- add alias-specific tests

Add a new test group exercising the Alias case:

```haskell
testAliasCycle :: TestTree
testAliasCycle =
  testGroup
    "alias body cycle detection"
    [ testCase "non-cyclic alias returns False" $ do
        innerVar <- mkVar (FlexVar (Just "a"))
        realVar <- mkVar (Structure (App1 ModuleName.basics "List" [innerVar]))
        var <- mkVar (Alias ModuleName.basics "MyList" [("a", innerVar)] realVar)
        result <- Occurs.occurs var
        result @?= False,
      testCase "cycle through alias realVar is detected" $ do
        var <- mkVar (FlexVar Nothing)
        let aliasArgs = [("a", var)]
        realVar <- mkVar (Structure (Fun1 var var))
        UF.set var (Descriptor (Alias ModuleName.basics "Fix" aliasArgs realVar) noRank noMark Nothing)
        result <- Occurs.occurs var
        result @?= True,
      testCase "cycle in realVar but not in args is detected" $ do
        argVar <- mkVar (FlexVar (Just "a"))
        var <- mkVar (FlexVar Nothing)
        realVar <- mkVar (Structure (App1 ModuleName.basics "List" [var]))
        UF.set var (Descriptor (Alias ModuleName.basics "Wrap" [("a", argVar)] realVar) noRank noMark Nothing)
        result <- Occurs.occurs var
        result @?= True
    ]
```

Register the new test group in the `tests` list at the top of the file.

## Verification

### Unit Tests

```bash
# Run the occurs check tests specifically
stack test --ta="--pattern Occurs"

# Run all type checker tests to verify no regressions
stack test --ta="--pattern Type"
```

### Manual Verification

Create a test Canopy source file that constructs a self-referential type
through an alias and verify the compiler rejects it with an infinite type error
rather than looping or crashing:

```elm
-- test-alias-cycle.can
type alias Fix a = { value : a, self : Fix a }

main = { value = 1, self = main }
```

### Build Verification

```bash
# Full build with warnings enabled
stack build --ghc-options="-Wall -Werror" 2>&1

# Full test suite
stack test
```

## Rollback Plan

The change is purely additive (one extra traversal step in the occurs check
and one extra rank adjustment).  Reverting is a single-line revert on each file.
There is no migration or data format change.
