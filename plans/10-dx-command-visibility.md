# Plan 10: CLI Command Visibility Fix

**Priority:** CRITICAL
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

Running `canopy` with no arguments shows only 5 commands: `repl`, `init`, `new`, `setup`, `reactor`. The most important daily-use commands — `make`, `test`, `install`, `fmt`, `lint` — are all classified as `Terminal.Uncommon` and hidden from the default help screen.

A new user who types `canopy` has no idea that `canopy make` exists.

## Files to Modify

### `packages/canopy-terminal/src/CLI/Commands/Build.hs`

- Line 31: Change `Terminal.Uncommon` to `Terminal.Common` for `make`
- Line 49: Change `Terminal.Uncommon` to `Terminal.Common` for `check`

### `packages/canopy-terminal/src/CLI/Commands/Dev.hs`

- Line 61: Change `Terminal.Uncommon` to `Terminal.Common` for `fmt`
- Line 73: Change `Terminal.Uncommon` to `Terminal.Common` for `lint`
- Line 85: Change `Terminal.Uncommon` to `Terminal.Common` for `test`

### `packages/canopy-terminal/src/CLI/Commands/Package.hs`

- Line 34: Change `Terminal.Uncommon` to `Terminal.Common` for `install`

### Resulting command visibility

**Common (shown in `canopy` overview):**
`make`, `check`, `install`, `test`, `fmt`, `lint`, `repl`, `init`, `new`, `setup`, `reactor`

**Uncommon (shown with `canopy --help-all` or similar):**
`publish`, `bump`, `diff`, `vendor`, `test-ffi`, `webidl`, `self-update`, `docs`, `audit`, `upgrade`, `migrate`, `bench`

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Run `canopy` with no arguments — verify `make`, `test`, `install`, `fmt`, `lint` are visible
