# Plan 25 — Fix hie.yaml for HLS Support

**Priority:** Tier 4 (DX)
**Effort:** 1 hour
**Risk:** None
**Files:** `hie.yaml`

---

## Problem

The `hie.yaml` at the repo root points to a `cabal` cradle with a `./compiler` path that doesn't exist. Haskell Language Server (HLS) cannot load the project, which means compiler contributors cannot use IDE features (go-to-definition, type info, error highlighting).

## Implementation

### Replace with stack multi-component cradle

```yaml
cradle:
  stack:
    - path: "packages/canopy-core/src"
      component: "canopy-core:lib"
    - path: "packages/canopy-query/src"
      component: "canopy-query:lib"
    - path: "packages/canopy-driver/src"
      component: "canopy-driver:lib"
    - path: "packages/canopy-builder/src"
      component: "canopy-builder:lib"
    - path: "packages/canopy-terminal/src"
      component: "canopy-terminal:lib"
    - path: "packages/canopy-terminal/impl"
      component: "canopy-terminal:lib"
    - path: "app"
      component: "canopy:exe:canopy"
    - path: "test"
      component: "canopy:test:canopy-test"
```

### Verify component names

```bash
stack ide targets
```

This lists all valid component names. Use the exact output to populate `hie.yaml`.

## Validation

```bash
# Start HLS and verify it loads
haskell-language-server-wrapper --project-ghc-version
# Open a source file in an editor with HLS and verify diagnostics appear
```

## Acceptance Criteria

- `hie.yaml` references all 6 packages with correct component names
- HLS can load any source file in any package
- No references to `./compiler` or other non-existent paths
