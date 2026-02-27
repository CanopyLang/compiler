# Plan 27 — Fix Weak Test Assertions

**Priority:** Tier 5 (Hardening)
**Effort:** 1 day
**Risk:** Low
**Files:** ~5 test files

---

## Problem

Several test files violate the project's own testing standards:

1. **`test/Unit/CLI/CommandsTest.hs`**: Every command test uses `length s > 0 @?= True` instead of verifying actual help text content.

2. **`test/Integration/JsonIntegrationTest.hs`**: Size-based assertions (`LBS.length > 10000 @?= True`) instead of structural checks.

3. **`test/Unit/FFI/ValidatorTest.hs`**: All assertions use `Text.isInfixOf` instead of exact matching — explicitly forbidden by CLAUDE.md.

## Implementation

### Fix 1: CommandsTest.hs — Verify actual command descriptions

```haskell
-- Before:
testCase "init command" $ do
  case initCommand of
    Terminal.Common s -> length s > 0 @?= True

-- After:
testCase "init command has correct summary" $ do
  case initCommand of
    Terminal.Common s -> s @?= "Create a Canopy project"
```

For each command, assert the exact summary text. If the summary changes, the test should be updated — that's the point of golden-style testing.

### Fix 2: JsonIntegrationTest.hs — Verify structure, not size

```haskell
-- Before:
LBS.length (B.toLazyByteString encoded) > 10000 @?= True

-- After:
let decoded = Aeson.decode (B.toLazyByteString encoded) :: Maybe Aeson.Value
assertBool "encoded JSON should be valid" (isJust decoded)
case decoded of
  Just (Aeson.Object obj) -> do
    assertBool "has 'type' field" (HashMap.member "type" obj)
    assertBool "has 'dependencies' field" (HashMap.member "dependencies" obj)
  _ -> assertFailure "expected JSON object"
```

### Fix 3: ValidatorTest.hs — Replace isInfixOf with exact matching

```haskell
-- Before:
assertBool "contains int validator" (Text.isInfixOf "typeof" result)

-- After:
result @?= expectedValidatorOutput
-- Where expectedValidatorOutput is the exact expected JS validator text
```

If the exact output is too long, use golden file testing:

```haskell
goldenVsString "int validator" "test/golden/validators/int.js" (pure (BSL.fromStrict (Text.encodeUtf8 result)))
```

### Step 4: Scan for other violations

```bash
# Find all weak assertions
grep -rn "isInfixOf\|length.*> 0.*@?=\|not.*null.*@?=" test/ --include="*.hs"
```

Fix each occurrence.

## Validation

```bash
make build && make test
```

## Acceptance Criteria

- Zero `length s > 0 @?= True` assertions in test code
- Zero `Text.isInfixOf` assertions in test code (use exact `@?=` or golden files)
- Zero `not (null x) @?= True` assertions
- All tests still pass with exact assertions
- `make build && make test` passes
