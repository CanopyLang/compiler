# Plan 11: Dual Command Type Unification

**Priority:** HIGH
**Effort:** Medium (1–3 days)
**Risk:** Medium — touches the CLI framework

## Problem

Two incompatible `Command` types coexist:

1. **`Terminal.Internal.Command`** — GADT with existentially quantified `args`/`flags`, used by the actual CLI dispatch (`Terminal.hs:131–181`), all command definitions, and `Terminal.Chomp` for argument parsing. This is the one that works.

2. **`Terminal.Types.Command`** — Record type with `CommandArgs = ()` and `CommandFlags = ()` (Terminal/Types.hs:248–250), used by `Terminal.Application`, `Terminal.Command`. The handler is hardcoded to `(() -> () -> IO ())`, losing all type safety.

The refactored `Terminal.Application` passes an **empty command list** to the overview handler (Application.hs:205) because the types are incompatible. `Terminal.Command.executeCommand` parses all commands with `Parser.noArgs` / `Parser.noFlags`, discarding actual argument specifications.

## Resolution

**Delete the broken refactored modules.** The GADT-based `Terminal.Internal.Command` is the correct design — it preserves type-safe argument/flag parsing. The "refactored" modules lost the type information.

### Files to Delete

- `packages/canopy-terminal/impl/Terminal/Types.hs` — or strip it down to only the types that don't duplicate `Internal`
- `packages/canopy-terminal/impl/Terminal/Application.hs` — empty command list bug
- `packages/canopy-terminal/impl/Terminal/Command.hs` — discards all arg/flag specs

### Files to Modify

- `packages/canopy-terminal/impl/Terminal.hs` — remove imports of deleted modules
- `packages/canopy-terminal/canopy-terminal.cabal` — remove deleted modules from `exposed-modules`
- Any file that imports `Terminal.Types`, `Terminal.Application`, or `Terminal.Command` — redirect to `Terminal.Internal`

### Alternative: Fix Instead of Delete

If the refactored modules serve a purpose (e.g., planned feature), fix them:
1. Make `Terminal.Types.Command` a wrapper around `Terminal.Internal.Command` (preserving the existential)
2. Fix `handleOverviewRequest` to extract commands from the actual `Terminal.Internal.Command` list
3. Fix `executeCommand` to use the real argument/flag parsers

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Run `canopy` — verify help overview shows all Common commands correctly
4. Run `canopy make --help` — verify flags are displayed
5. Verify no remaining references to `CommandArgs = ()` or `CommandFlags = ()`
