# Plan 13: Test Filter Implementation

**Priority:** MEDIUM
**Effort:** Medium (1–3 days)
**Risk:** Low

## Problem

The `--filter` flag for `canopy test` is parsed by the CLI (Dev.hs:183, Test.hs:731–739) but never used. The `_testFilter` field exists in the `Flags` record but the comment at Test.hs:798–801 says "not yet used in the harness."

## Files to Modify

### `packages/canopy-terminal/src/Test.hs`

1. **Thread filter through compilation**: Pass `_testFilter` from `Flags` into `compileAndRunTests` (line 256)

2. **Pass filter to harness**: The test harness JavaScript generators need to accept the filter string and inject it into the test runner configuration

3. **Remove the suppression**: Delete lines 798–801 (`_suppressUnusedFilter`)

### `packages/canopy-terminal/src/Test/Harness.hs`

1. **Accept filter parameter** in harness generation functions

2. **Inject filter into runner JS**: The generated JavaScript test runner should check each test name against the filter pattern before executing:
   ```javascript
   const filter = "__FILTER_PATTERN__";
   // In the test runner loop:
   if (filter && !testName.includes(filter)) { skip(); continue; }
   ```

### `packages/canopy-terminal/src/Test/External.hs`

For external (Node.js async) tests, pass the filter as a command-line argument or environment variable to the test process.

### Browser Tests

For Playwright-based browser tests, pass the filter through the launcher script to the browser test environment.

## Design Notes

- Filter should be a simple substring match (like `--ta="--pattern"` in tasty)
- Case-insensitive matching is more user-friendly
- Print which tests were skipped due to filter: `Skipping 12 tests not matching "Router"`

## Verification

1. `make build` — zero warnings
2. `make test` — all tests pass
3. Create test project with multiple test modules
4. Run `canopy test --filter "ModuleName"` — verify only matching tests run
5. Run `canopy test` without filter — verify all tests run
