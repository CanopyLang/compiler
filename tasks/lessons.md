# Lessons Learned

## 2026-03-14: Code Quality Overhaul

### Subagent Isolation is Non-Negotiable

**Problem**: Launched 3 subagents (operator-refactor, validate-imports, let-to-where-refactor) in the main worktree simultaneously. They all modified files concurrently, creating conflicts with each other and with manual edits.

**Damage caused**:
- Import agent renamed module paths `FFI.*` → `ForeignFFI.*` (broke file/module name matching)
- Import agent qualified operators like `</>` that must stay unqualified
- Operator agent created broken `(do)` syntax from `$ do` blocks
- 238 files modified with broken changes, had to `git checkout .` to recover
- Multiple `stack build` processes running simultaneously caused lock conflicts

**Rule**: Always use `isolation: "worktree"` when launching subagents. Never run subagents in the main worktree. Never run multiple agents in parallel on the same worktree.

### Watch Build Output Directly

**Problem**: Piping build output to `tail -20` or running builds in background hid critical error messages. Could not see which compilation step failed.

**Rule**: Always run `make build` and `make test` directly, watching the full output. No `2>&1 | tail`, no `run_in_background: true` for builds.

### One Stack Instance at a Time

**Problem**: Running `make build` while another `stack test` was in progress caused "cannot satisfy -package-id" errors from corrupted build cache.

**Rule**: Wait for one Stack command to finish before starting another. If build cache gets corrupted, run `stack clean` before retrying.

### Import Agents Must Not Rename Modules

**Problem**: The validate-imports agent interpreted `FFI` as an abbreviation and expanded it to `ForeignFFI`, changing module declarations and import paths. This broke the build because Haskell module names must match file paths.

**Rule**: Import qualification agents must ONLY add the `qualified` keyword and adjust usage sites. They must NEVER rename modules, change module declarations, or expand abbreviations in module paths.

### TH Staging Order Matters

**Problem**: Placed `makeLenses ''SourceMap` between the SourceMap and Mapping type definitions. Since SourceMap contains Mapping fields, TH couldn't see the Mapping type and failed with "Not in scope: type constructor 'Mapping'".

**Rule**: `makeLenses` must be placed AFTER all types it depends on are defined. If type A contains type B, put `makeLenses ''A` after B's definition.

### TH Staging Blocks Cross-Stage References

**Problem**: Tried to add `makeLenses ''ExtractedFFI` in FFI.hs. The splice created a stage boundary that prevented functions defined before the splice from seeing functions defined after it. Since ExtractedFFI was defined in the middle of the file, this broke half the module.

**Rule**: If a type is defined in the middle of a file with functions before and after it, `makeLenses` via TH may not work. Either move the type to the top of the file, or define lenses manually.
