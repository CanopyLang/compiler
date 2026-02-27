# Plan 33 — Integrate canopy-webidl into Build

**Priority:** Tier 6 (Strategic)
**Effort:** 1 day
**Risk:** Low
**Files:** `stack.yaml`, `packages/canopy-webidl/canopy-webidl.cabal`

---

## Problem

`canopy-webidl` is a complete WebIDL parser and Canopy FFI generator (11 source files, `.cabal` with library + executable + tests), but it is not listed in `stack.yaml`. It cannot be built with `make build` or `stack build`. It uses dependencies (`megaparsec`, `http-conduit`) not in the main resolver configuration.

## Implementation

### Step 1: Add to stack.yaml

```yaml
packages:
  - .
  - packages/canopy-core
  - packages/canopy-query
  - packages/canopy-driver
  - packages/canopy-builder
  - packages/canopy-terminal
  - packages/canopy-webidl   # ADD THIS
```

### Step 2: Add missing dependencies to extra-deps

```bash
cd packages/canopy-webidl
stack build 2>&1 | grep "not present in build plan"
```

For each missing dependency, add to `stack.yaml` extra-deps with a pinned version:

```yaml
extra-deps:
  - megaparsec-9.x.x
  - http-conduit-2.x.x
  # etc.
```

### Step 3: Verify canopy-webidl builds

```bash
stack build canopy-webidl
stack test canopy-webidl
```

### Step 4: Add Makefile targets

```makefile
build-webidl:
	@stack build canopy-webidl

test-webidl:
	@stack test canopy-webidl
```

### Step 5: Add to top-level test suite (optional)

If the WebIDL tests are independent (no network access needed), add them to the CI test run.

## Validation

```bash
stack build canopy-webidl
stack test canopy-webidl
make build && make test  # Verify no regression
```

## Acceptance Criteria

- `stack build canopy-webidl` succeeds
- `stack test canopy-webidl` passes
- `canopy-webidl` is listed in `stack.yaml`
- `make build` still succeeds (no regression)
