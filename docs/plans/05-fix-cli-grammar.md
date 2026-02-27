# Plan 05 — Fix Grammar Errors in CLI Help Text

**Priority:** Tier 0 (Blocker)
**Effort:** 30 minutes
**Risk:** None
**Files:** `packages/canopy-terminal/src/CLI/Commands.hs`

---

## Problem

The CLI help text contains grammar errors and casing inconsistencies that undermine professionalism:

1. "Start an Canopy project" — should be "a Canopy project" (3 occurrences)
2. "when you click on an Canopy file" — should be "a Canopy file"
3. "Canopy publish https://..." — binary name is `canopy` (lowercase), not `Canopy`

## Implementation

### Step 1: Find and fix all "an Canopy" occurrences

```bash
grep -n "an Canopy\|an canopy" packages/canopy-terminal/src/CLI/Commands.hs
```

Replace every `an Canopy` with `a Canopy` and every `an canopy` with `a canopy`.

### Step 2: Fix binary name casing in examples

Search for `"Canopy "` (capitalized followed by space) in contexts where it's used as a command example. Command examples should show `canopy` (lowercase) since that's the actual binary name:

```bash
grep -n '"Canopy ' packages/canopy-terminal/src/CLI/Commands.hs
```

In prose/titles, "Canopy" (capitalized) is correct. In command examples and shell snippets, `canopy` (lowercase) is correct.

### Step 3: Search for other grammar issues

```bash
grep -rn "an Canopy\|an canopy\|an Elm\|an elm" packages/canopy-terminal/src/
grep -rn "an Canopy\|an canopy" packages/canopy-terminal/impl/
```

Fix any additional occurrences.

## Validation

```bash
make build && make test
canopy --help  # Visual inspection
canopy init --help  # Visual inspection
```

## Acceptance Criteria

- Zero occurrences of "an Canopy" or "an canopy" in any source file
- Command examples use lowercase `canopy`
- All tests pass
