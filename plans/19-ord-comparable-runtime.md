# Plan 19: Ord/Comparable Runtime Support for Custom Types

## Problem

`deriving (Ord)` sets `ComparableBound` in the type system, allowing types to be used as Dict keys, Set members, and with `compare`/`<`/`>`. However, `_Utils_cmp` in `Elm/Kernel/Utils.js` only handles primitives, tuples, and lists at runtime. Custom union types with constructor arguments produce **wrong results**.

### Current `_Utils_cmp` Branches

| Branch | Prod mode check | Handles |
|--------|----------------|---------|
| Primitive | `typeof x !== 'object'` | Int, Float, String, Char |
| Tuple | `typeof x.$ === 'undefined'` | `(a, b)`, `(a, b, c)` |
| List | fallthrough (iterative `.b` traversal) | `List a` |
| **Custom types** | **MISSING** | `{ $: int, a: v1, b: v2, ... }` |

### Why It's Hard

In prod mode, list cons cells (`{ $: 1, a: head, b: tail }`) are **structurally identical** to 2-arg custom type values (`{ $: 0, a: arg1, b: arg2 }`). The `$` tag spaces overlap (both use non-negative integers). There is no runtime marker distinguishing lists from custom types.

### What Already Works

- **Enum unions** (all nullary constructors): Bare integers in prod mode. `_Utils_cmp` handles via primitive branch.
- **Type system**: `ComparableBound` propagation, `extractBoundsFromUnions`, unification — all correct.
- **Validation**: `validateOrdType` rejects functions and extensible records.

## Options Evaluated

### Option A: Restrict `deriving (Ord)` to Enums Only

- Zero runtime changes needed — enum types already compare correctly
- Add compile-time error for non-enum unions with `deriving (Ord)`
- Simple, safe, ships immediately
- **Downside**: Can't use `Card Suit Int` as a Dict key

### Option B: Generic `_Utils_cmp` Extension

- Replace the list-specific fast path with generic `for (var key in x)` iteration
- Works for both lists and custom types
- **Downside**: Loses iterative list optimization (recursive instead), potential stack overflow on long lists
- **Downside**: Cannot distinguish list nil/cons from custom types with same arity in prod mode — the `$` tag ordering of list constructors (nil=0, cons=1) vs custom constructors may produce surprising cross-type comparison if somehow mixed

### Option C: Per-Type Comparison Functions via `__cmp` Marker

- Attach `__cmp` function reference to each constructed value
- `_Utils_cmp` checks `if (x.__cmp) return x.__cmp(x, y)`
- **Downside**: Memory overhead — every value carries extra reference
- **Downside**: Changes constructor representation

### Option D: Reserved List Tags (Negative `$`)

- Change list nil/cons to use negative `$` values (like Dict already does)
- `_Utils_cmp` uses `x.$ < 0` for list fast-path, `x.$ >= 0` for custom types
- Clean separation, minimal runtime overhead
- **Downside**: Changes list representation — affects List kernel, pattern matching codegen, case expression codegen

### Option E: Type-Class Dictionary Passing (Long-term)

- Generate per-type `compare` functions
- Thread comparison functions through Dict/Set operations
- True type class dispatch like Haskell
- **Downside**: Massive change to compilation pipeline, not feasible short-term

## Recommended Approach: Option A Now, Option D Later

### Phase 1 (This PR): Enum-Only Restriction

Restrict `deriving (Ord)` to unions where ALL constructors are nullary (enum types). These already work at runtime. Add a clear error for non-enum types.

### Phase 2 (Future PR): Option D — Reserved List Tags

Change list representation to use negative `$` values, then extend `_Utils_cmp` with a generic custom-type branch. This enables `deriving (Ord)` on all union types.

---

## Phase 1: Enum-Only `deriving (Ord)`

### 1.1 Strengthen Validation

**File**: `packages/canopy-core/src/Canonicalize/Environment/Local.hs`

In `validateOneUnionClause`, when handling `DeriveOrd`, check that all constructors are nullary:

```haskell
Can.DeriveOrd ->
  validateOrdIsEnum typeName alts
```

Where `validateOrdIsEnum` checks every `Can.Ctor` has zero arguments. If any constructor has arguments, produce a new error: `DerivingOrdRequiresEnum typeName ctorName`.

### 1.2 New Error Variant

**File**: `packages/canopy-core/src/Reporting/Error/Canonicalize.hs`

Add to `DerivingProblem`:

```haskell
| DerivingOrdRequiresEnum Name.Name Name.Name
-- typeName, first ctor with args
```

Error message:

```
-- DERIVING ERROR --------------------------------------------------------- X.canopy

The type `Card` cannot derive `Ord` because constructor `Card` has arguments.

6| type Card = Card Suit Int
                    ^^^^^^^^

Currently, `deriving (Ord)` only works on enum types where all constructors
have zero arguments. For example:

    type Color = Red | Green | Blue
        deriving (Ord)

Support for comparing types with constructor arguments is planned for a
future release.
```

### 1.3 Alias Ord Validation

**File**: `packages/canopy-core/src/Canonicalize/Environment/Local.hs`

For aliases, `deriving (Ord)` should also be restricted. Record aliases can't be compared (Elm records aren't comparable). Type aliases that resolve to comparable types (like `type Age = Int`) could work, but for simplicity, reject all alias `deriving (Ord)` in Phase 1 and only allow it on enum unions.

Add validation in `validateOneAliasClause`:

```haskell
Can.DeriveOrd ->
  Result.throw (Error.DerivingInvalid typeName (DerivingOrdNotOnUnion typeName))
```

### 1.4 Keep Existing Type System Wiring

`ComparableBound` propagation for enum unions already works:
- `extractBoundsFromUnions` registers the bound
- Unification resolves `comparable` constraints
- `_Utils_cmp` handles bare integers correctly

No changes needed to `Type/Solve.hs`, `Type/Unify.hs`, or `_Utils_cmp`.

### Files Modified (Phase 1)

| File | Changes |
|------|---------|
| `Canonicalize/Environment/Local.hs` | Validate Ord is enum-only, reject alias Ord |
| `Reporting/Error/Canonicalize.hs` | Add `DerivingOrdRequiresEnum`, `DerivingOrdNotOnUnion` |

---

## Phase 2: Full Custom Type Comparison (Future)

### 2.1 Change List Representation

**File**: `core-packages/core/src/Elm/Kernel/List.js`

```javascript
// Before:
var _List_Nil = { $: 0 };
function _List_Cons(hd, tl) { return { $: 1, a: hd, b: tl }; }

// After:
var _List_Nil = { $: -1 };
function _List_Cons(hd, tl) { return { $: -2, a: hd, b: tl }; }
```

### 2.2 Update Pattern Matching Codegen

**File**: `packages/canopy-core/src/Generate/JavaScript/Expression/Case.hs`

Update `ctorTag` and `ctorSwitchExpr` to use negative tags for list constructors in prod mode. The dev mode string tags (`':'` and `'[]'`) remain unchanged.

### 2.3 Extend `_Utils_cmp`

**File**: `core-packages/core/src/Elm/Kernel/Utils.js`

```javascript
function _Utils_cmp(x, y, ord)
{
    if (typeof x !== 'object')
    {
        return x === y ? 0 : x < y ? -1 : 1;
    }

    // Tuples (no $ field)
    /**__PROD/
    if (typeof x.$ === 'undefined')
    //*/
    /**__DEBUG/
    if (x.$[0] === '#')
    //*/
    {
        return (ord = _Utils_cmp(x.a, y.a))
            ? ord
            : (ord = _Utils_cmp(x.b, y.b))
                ? ord
                : _Utils_cmp(x.c, y.c);
    }

    // Lists (negative $ tags) — iterative for performance
    /**__PROD/
    if (x.$ < 0)
    //*/
    /**__DEBUG/
    if (x.$ === ':' || x.$ === '[]')
    //*/
    {
        for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {}
        return ord || (x.b ? 1 : y.b ? -1 : 0);
    }

    // Custom union types (non-negative $ tags)
    // Compare constructor tag first, then fields left-to-right
    ord = _Utils_cmp(x.$, y.$);
    if (ord) return ord;
    for (var key in x)
    {
        if (key !== '$')
        {
            ord = _Utils_cmp(x[key], y[key]);
            if (ord) return ord;
        }
    }
    return 0;
}
```

### 2.4 Remove Enum-Only Restriction

Update validation in `Canonicalize/Environment/Local.hs` to allow `deriving (Ord)` on all union types (keeping the existing field-type validation that rejects functions/records).

### 2.5 Update `_Utils_equal`

The `_Utils_eqHelp` function checks `x.$ < 0` for Dict nodes. With lists also negative, update:

```javascript
// Dict nodes: $ is -1 or -2 (RBNode, RBEmpty)
// List nodes: $ is -1 or -2 (Nil, Cons)  -- COLLISION!
```

**Problem**: Dict and List would collide in the negative `$` space. Use different ranges:
- List: `$: -1` (nil), `$: -2` (cons)
- Dict: `$: -3` (RBNode), `$: -4` (RBEmpty)

Or use a different scheme entirely. The key constraint is that `_Utils_eqHelp` uses `x.$ < 0` to detect Dict/Set for conversion to list before comparison. We need:

```javascript
// Reserve: -1, -2 for List; -3, -4 for Dict
// _Utils_eqHelp checks x.$ <= -3 for Dict
```

### Phase 2 Files Modified

| File | Changes |
|------|---------|
| `Elm/Kernel/List.js` | Nil=$:-1, Cons=$:-2 |
| `Elm/Kernel/Utils.js` | Add custom type branch, update list check |
| `Generate/JavaScript/Expression/Case.hs` | Update list pattern tags |
| `Generate/JavaScript/Kernel.hs` | Update Dict tag generation |
| `Canonicalize/Environment/Local.hs` | Remove enum-only restriction |

### Phase 2 Risks

- **Breaking change**: List/Dict internal representation changes
- **Cache invalidation**: All `.elco` artifacts must be regenerated
- **Package recompilation**: All core packages need rebuild
- **Extensive testing**: Pattern matching, equality, Dict/Set operations all need verification

---

## Verification

### Phase 1

1. `stack build canopy-core` — no warnings
2. `make test` — all tests pass
3. `type Color = Red | Green | Blue deriving (Ord)` — compiles, works as Dict key
4. `type Card = Card Suit Int deriving (Ord)` — produces clear compile error
5. `type alias Age = Int deriving (Ord)` — produces clear compile error

### Phase 2 (when implemented)

1. All Phase 1 tests still pass
2. `type Card = Card Suit Int deriving (Ord)` — compiles, works as Dict key
3. `Dict.fromList [(Card Hearts 10, "x"), (Card Spades 3, "y")]` — correct ordering
4. `List.sort [Card Spades 3, Card Hearts 10]` — correct ordering
5. `List.sort [1, 3, 2]` — still works (list comparison unchanged)
6. `Dict.insert "key" 1 Dict.empty` — still works (Dict operations unchanged)
7. No stack overflow on `List.sort` with 100k+ element lists
