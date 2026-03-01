# Plan 12: Build Progress Indicators

**Priority:** HIGH
**Effort:** Medium (1–3 days)
**Risk:** Low

## Problem

Without `--verbose`, the user sees nothing during compilation. No progress bar, no "Compiling Module.Name", no module count. For large projects, it looks like the compiler is hung. All logging is gated behind `CANOPY_LOG` or `--verbose`.

## Design

Add unconditional progress output (not gated by verbose flag) at these points:

1. **Before compilation**: `Compiling 47 modules...`
2. **Per-module progress**: `[3/47] Compiling App.Utils` (only when > 5 modules)
3. **After compilation**: `Compiled 47 modules in 1.2s` or error summary
4. **Code generation**: `Generating JavaScript to build/main.js`

## Files to Modify

### `packages/canopy-terminal/src/Make.hs`

1. Add a `ProgressReporter` type that writes to stderr:
   ```haskell
   data ProgressReporter = ProgressReporter
     { _prTotal :: !Int
     , _prCurrent :: !(IORef Int)
     }
   ```

2. Before calling `Builder.buildFromExposed` or `Builder.buildFromPaths`, count total modules and print the header

3. Pass a progress callback into the build pipeline that increments and prints per-module progress

4. After build completes, print timing summary

### `packages/canopy-builder/src/Builder.hs`

Accept an optional progress callback (`Maybe (ModuleName -> IO ())`) in the compilation functions. Call it after each module completes.

### `packages/canopy-terminal/src/Make/Output.hs`

Print code generation targets unconditionally (not verbose-gated):
- Line 130: `"Generating JavaScript to: ..."` — make unconditional
- Line 228: `"Generating HTML to: ..."` — make unconditional
- Lines 187–194: Code splitting summary — make unconditional

### Output Format

```
Dependencies loaded (0.1s)
Compiling 47 modules...
  [12/47] Compiling App.Router
  [13/47] Compiling App.Utils
  ...
Compiled 47 modules (1.2s)
Generating JavaScript to build/main.js
Success!
```

For small projects (≤5 modules), skip per-module output:
```
Compiling 3 modules... done (0.3s)
Generating JavaScript to build/main.js
Success!
```

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Compile a multi-module project — verify progress output appears without `--verbose`
4. Verify `--quiet` flag suppresses progress output (if such flag exists, otherwise add one)
