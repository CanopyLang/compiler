# Plan 21: Wildcard Pattern Audit

**Priority:** MEDIUM
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

~15 wildcard patterns (`_ ->`) in the code generator could silently accept new AST variants without specialized handling. If a new `Opt.Expr`, `Opt.Def`, or `Mode` variant is added, these wildcards won't trigger a compiler warning.

## Key Locations

### `Generate/JavaScript/Expression.hs`
- Line 150: `_ ->` on `(def, body)` — matches any Def variant + any Expr variant
- Line 565: `_ -> []` on `getTailDefArgs` — returns empty list for non-TailDef
- Line 693: `_ ->` in `crushIfs` — matches any non-If expression

### `Generate/JavaScript/Expression/Call.hs`
- Lines 78–81: `_ -> generateCallHelp` — catches all non-VarBox/non-VarGlobal function calls
- Lines 148, 180, 225: `_ ->` on global call patterns — fall through to `generateGlobalCall`
- Lines 287, 321, 345, 364: `_ ->` on operator optimization patterns

### `Generate/JavaScript/Kernel.hs`
- Line 128: `Mode.Dev _ _ _ _ _ ->` — 5 wildcard fields hide future Dev constructor changes

### `AST/Optimized/Graph.hs`
- Lines 219–220: `addKernelDepSimple` has `_ -> deps` — silently ignores new `Kernel.Chunk` variants

### `Generate/JavaScript/StringPool.hs`
- Line 90: `Opt.Cycle _ values functions _ ->` — ignores some Cycle fields that might contain poolable strings

## Solution

For each wildcard, evaluate whether it should be replaced with explicit pattern matching:

### Replace with explicit patterns (catches new variants at compile time)
```haskell
-- BEFORE:
getTailDefArgs = \case
  Opt.TailDef _ args _ -> args
  _ -> []

-- AFTER:
getTailDefArgs = \case
  Opt.TailDef _ args _ -> args
  Opt.Def _ _ _ -> []
```

### Use `-Wincomplete-patterns` where missing
Ensure all code generation modules have `{-# OPTIONS_GHC -Wall #-}` which includes `-Wincomplete-patterns`.

### For legitimate catch-alls, add a comment
```haskell
-- All other expressions use generic call handling.
-- If a new Opt.Expr variant needs special call handling, add a case above.
_ -> generateCallHelp mode expr args
```

## Verification

1. `make build` — zero warnings (with `-Wall`)
2. `make test` — all tests pass
3. Add a `-- WILDCARD AUDIT: <reason>` comment to every remaining intentional wildcard
4. Count remaining wildcards in `Generate/` — document each with justification
