# Plan 31 — Remove allow-newer from stack.yaml

**Priority:** Tier 6 (Strategic)
**Effort:** 1 day
**Risk:** Medium (may surface dependency conflicts)
**Files:** `stack.yaml`, possibly `.cabal` files

---

## Problem

`stack.yaml` contains `allow-newer: true`, which globally disables version upper-bound checking. This means any Stackage update could silently pull in incompatible dependency versions. The compiler's own build is not fully reproducible from a security standpoint.

## Implementation

### Step 1: Remove allow-newer

```yaml
# Before:
allow-newer: true

# After:
# (line removed entirely)
```

### Step 2: Build and identify conflicts

```bash
stack build 2>&1 | tee /tmp/version-conflicts.txt
```

### Step 3: Fix each conflict

For each version bound violation:

**Option A (preferred):** Update the `.cabal` file to widen the version bound to accommodate the resolver's version:

```yaml
# In canopy-core.cabal:
build-depends:
  containers >= 0.6 && < 0.8  -- widen upper bound
```

**Option B:** Pin the specific version in `stack.yaml` extra-deps:

```yaml
extra-deps:
  - problematic-package-1.2.3
```

**Option C:** If the conflict is with our own packages, update the version constraints between them.

### Step 4: Verify the lock file

```bash
stack build
cat stack.yaml.lock  # Verify all deps are pinned
```

### Step 5: Document version policy

Add a comment in `stack.yaml`:

```yaml
# IMPORTANT: Do not add allow-newer: true
# All version bounds must be explicitly managed.
# If a dependency conflict arises, fix the bound or pin the version.
```

## Validation

```bash
make build && make test
```

## Acceptance Criteria

- `allow-newer` does not appear in `stack.yaml`
- `stack build` succeeds without any `allow-newer` flag
- All dependency version bounds are explicit and correct
- `make build && make test` passes
