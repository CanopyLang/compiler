# Identity Polymorphism Bug - Investigation Summary

## Status: Unable to Reproduce

I conducted an extensive investigation but could not reproduce the bug with simplified test cases.

## What Was Attempted

### Test Cases (10 created, all PASS)
- `/home/quinten/fh/canopy/test/fixtures/type/IdentityPolymorphism*.elm`
- Covering: basic identity, `<<` composition, polymorphic types, multiple branches, records

### Code Analysis
- Traced `makeCopy` and `restore` mechanisms in `Type/Solve.hs`
- Analyzed case branch constraint generation in `Type/Constrain/Expression.hs`
- Reviewed environment management and variable generalization
- Identified the constraint solving order (left-to-right with state threading)

### Findings
The error shows `identity` typed as `AnalyticsNew.Msg -> AnalyticsNew.Msg` instead of polymorphic, suggesting:

1. **Type variable pollution** between case branches
2. **makeCopy reusing stale copies** instead of creating fresh ones
3. **Generalization failure** for let-bound `helper` function

## Why Reproduction Failed

The bug likely requires a specific combination of:
- Large file size (Main.elm has many branches)
- Specific type structure or nesting
- Interaction between multiple polymorphic functions
- Something in the actual Main.elm not present in simplified tests

## Next Steps Options

### Option 1: Debug Logging
I added (commented-out) debug logging to `makeCopy`:
```haskell
-- Uncomment putStrLn lines in packages/canopy-core/src/Type/Solve.hs:643-650
-- Rebuild and compile Main.elm to capture type inference trace
```

### Option 2: Minimal Reproduction
Extract from Main.elm:
- Just the `view` function
- Only AnalyticsNew and Analytics branches
- Necessary type definitions
- Test if it fails standalone

### Option 3: Speculative Fix
Modify `makeCopy` to be more aggressive about creating fresh copies:
- Clear ALL cached copies before starting
- Verify variables are properly generalized
- Add assertions to catch pollution

### Option 4: Workaround
Modify Main.elm temporarily:
- Add explicit type annotation to `helper`
- Inline `viewPage` instead of using let binding
- Split case expression into smaller functions

## Files Modified

- `packages/canopy-core/src/Type/Solve.hs` - Added debug logging (commented)

## Files Created

- `docs/IDENTITY_POLYMORPHISM_BUG_INVESTIGATION.md` - Full investigation notes
- `docs/IDENTITY_BUG_SUMMARY.md` - This file
- 10 test fixtures in `test/fixtures/type/`

## Recommendation

To proceed, I need either:
1. Ability to compile Main.elm with debug output
2. A minimal reproduction extracted from Main.elm
3. Permission to implement a speculative fix based on theory

The bug is real (Elm compiles it, Canopy doesn't), but without reproduction, any fix would be speculative and risk breaking working code.
