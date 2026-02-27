# Plan 01 — Remove HTTP_DEBUG Print Statements

**Priority:** Tier 0 (Blocker)
**Effort:** 30 minutes
**Risk:** None
**Files:** `packages/canopy-builder/src/Http.hs`

---

## Problem

`Http.hs` contains 9 `putStrLn "HTTP_DEBUG: ..."` statements in the `getArchiveWithHeaders` function (lines 681-717). These fire on every package download, leaking internal URLs to stdout and making the tool appear unfinished. Any evaluator or first-time user will see these immediately.

## Evidence

```haskell
-- Http.hs ~line 681
putStrLn ("HTTP_DEBUG: Starting archive download from " <> url)
putStrLn ("HTTP_DEBUG: Downloading HTTP archive from " <> url)
putStrLn ("HTTP_DEBUG: Got HTTP response, reading archive content")
-- ... 6 more
```

## Implementation

### Step 1: Remove all HTTP_DEBUG statements

Search for `HTTP_DEBUG` in `Http.hs` and delete every line containing it. These are bare `putStrLn` calls, not wired into any logging framework.

```bash
grep -n "HTTP_DEBUG" packages/canopy-builder/src/Http.hs
```

Delete each matching line. The surrounding code does not depend on these statements — they are interleaved between actual logic lines.

### Step 2: Replace with structured logging (optional)

If any of these debug points are genuinely useful, replace them with the existing `Logging.Logger` infrastructure:

```haskell
-- Instead of: putStrLn ("HTTP_DEBUG: Starting archive download from " <> url)
-- Use: Logger.debug "Http" ("Starting archive download from " <> Text.pack url)
```

However, the recommended approach is to simply delete them. The structured logging system (`Logging/Logger.hs`) already exists for when debug output is actually needed — it is gated behind `CANOPY_LOG_LEVEL` environment variable.

### Step 3: Search for other debug prints

```bash
grep -rn "putStrLn.*DEBUG\|putStrLn.*debug\|print.*DEBUG" packages/*/src/
```

Remove any other debug print statements found in production code.

## Validation

```bash
make build && make test
```

All 2,376 tests must pass. Manually run `canopy install` on a test project and verify no debug output appears on stdout.

## Acceptance Criteria

- Zero `putStrLn` calls containing "DEBUG" in any `packages/*/src/` file
- `make build` produces no warnings related to these changes
- `make test` passes all tests
