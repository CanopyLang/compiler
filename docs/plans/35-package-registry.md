# Plan 35 — Package Registry MVP

**Priority:** Tier 6 (Strategic)
**Effort:** 2 weeks
**Risk:** High (new service, infrastructure required)
**Files:** New package or repository

---

## Problem

Without a running `package.canopy-lang.org`, there is no ecosystem. Users cannot install packages. The compiler falls back to `package.elm-lang.org` for Elm packages, but Canopy-specific packages (canopy/core, canopy/test, canopy/debug) need a registry.

This is the single biggest adoption blocker.

## Design Options

### Option A: Static Registry (MVP — recommended first)

A static JSON file hosted on GitHub Pages or a CDN. No server-side logic. Packages are submitted via pull request.

```
package.canopy-lang.org/
├── all-packages           -- JSON list of all packages
├── all-packages/since/N   -- packages added after sequence N
├── packages/
│   ├── canopy/core/
│   │   ├── 1.0.5/
│   │   │   ├── canopy.json
│   │   │   ├── docs.json
│   │   │   └── endpoint.json  -- { "url": "...", "hash": "sha256:..." }
│   │   └── releases.json
│   └── canopy/test/
│       └── ...
```

**Pros:** Zero infrastructure cost, zero maintenance, fully reproducible.
**Cons:** No dynamic features (search, popularity, download counts).

### Option B: Dynamic Registry

A Haskell server (Servant/Warp) that handles package upload, validation, documentation generation, and search.

**Pros:** Full-featured, Elm-compatible API.
**Cons:** Infrastructure cost, maintenance burden, availability requirements.

### Recommended: Start with Option A, migrate to Option B later.

## Implementation (Option A)

### Step 1: Create registry repository

```
canopy-packages/
├── packages/
│   ├── canopy/
│   │   ├── core/
│   │   │   └── 1.0.5/
│   │   │       ├── canopy.json
│   │   │       ├── src/          -- or archive URL
│   │   │       └── docs.json
│   │   ├── test/
│   │   │   └── 1.0.0/
│   │   └── debug/
│   │       └── 1.0.0/
│   └── elm/            -- mirrors of elm packages
│       ├── core/
│       ├── html/
│       ├── json/
│       ├── browser/
│       └── ...
├── all-packages.json
├── CONTRIBUTING.md      -- how to submit packages
└── .github/
    └── workflows/
        └── validate.yml -- CI: validate package on PR
```

### Step 2: Create all-packages index

```json
[
  {"name": "canopy/core", "versions": ["1.0.5"], "summary": "Core language primitives"},
  {"name": "canopy/test", "versions": ["1.0.0"], "summary": "Testing framework"},
  {"name": "elm/core", "versions": ["1.0.5"], "summary": "Elm core (compatibility)"},
  {"name": "elm/html", "versions": ["1.0.0"], "summary": "HTML rendering"},
  {"name": "elm/json", "versions": ["1.1.3"], "summary": "JSON encoding/decoding"}
]
```

### Step 3: Host on GitHub Pages

Configure the repository for GitHub Pages serving from the `main` branch. Set up CNAME for `package.canopy-lang.org`.

### Step 4: Update compiler to use the registry

In `Http.hs`, configure the registry URL:

```haskell
registryUrl :: String
registryUrl = "https://package.canopy-lang.org"
```

The existing `allPackagesUrl`, `packageUrl`, etc. should point to the static registry.

### Step 5: Mirror essential Elm packages

For each Elm package referenced in `Package.hs` (core, html, json, browser, url, http, bytes, file, time, random, virtual-dom), create a mirror entry in the registry with the original Elm source and a Canopy-compatible `canopy.json`.

### Step 6: Package submission workflow

Document in `CONTRIBUTING.md`:

1. Fork the registry repo
2. Add your package to `packages/<author>/<name>/<version>/`
3. Include `canopy.json`, `src/`, and `README.md`
4. Open a pull request
5. CI validates the package compiles and passes tests
6. Maintainer merges, GitHub Pages deploys

### Step 7: CI validation

Create a GitHub Action that:
1. Checks `canopy.json` is valid
2. Verifies the package compiles with `canopy make`
3. Runs `canopy test` if tests exist
4. Generates `docs.json`
5. Computes SHA-256 of the package archive

### Step 8: Integrate with lock file (Plan 21)

The lock file records SHA-256 hashes. The static registry provides hashes in `endpoint.json`. The compiler verifies downloads match.

## Validation

```bash
# Verify compiler can fetch from the registry:
canopy init test-project
cd test-project
canopy install elm/html
canopy make src/Main.can
```

## Acceptance Criteria

- `package.canopy-lang.org` resolves and serves package index
- `canopy install canopy/core` succeeds
- `canopy install elm/html` succeeds (via mirror)
- Package submission via PR is documented and has CI validation
- All core Elm packages are mirrored
- SHA-256 hashes are available for all packages
