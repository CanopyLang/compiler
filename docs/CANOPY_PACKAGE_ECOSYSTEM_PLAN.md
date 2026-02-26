# Canopy Package Ecosystem Architecture Plan

## Executive Summary

You need to fork ~15 Elm core packages and rewrite them with your new FFI system. Based on research, the recommended approach is a **hybrid architecture**: a separate "canopy-packages" monorepo that lives alongside the compiler, with optional git submodule linking for tight integration during development.

---

## Current State Analysis

### What Exists Today

- 3 packages in `core-packages/`: `canopy/core`, `canopy/test`, `canopy/debug`
- Dependencies still reference `elm/*` packages (compatibility mode)
- New FFI system with JSDoc-based type contracts
- Documented 4-phase migration plan (elm/* → canopy/*)

### Elm Packages That Need Forking

| Package | Priority | Reason |
|---------|----------|--------|
| `elm/core` | Done | `canopy/core` exists |
| `elm/browser` | High | Required for all web apps |
| `elm/html` | High | DOM manipulation |
| `elm/virtual-dom` | High | Foundation for html/svg |
| `elm/json` | High | Data interchange |
| `elm/url` | High | Routing/navigation |
| `elm/http` | High | Network requests |
| `elm/time` | Medium | Time/dates |
| `elm/random` | Medium | Randomness |
| `elm/file` | Medium | File handling |
| `elm/bytes` | Medium | Binary data |
| `elm/parser` | Medium | Parsing combinators |
| `elm/regex` | Low | Regular expressions |
| `elm/svg` | Low | SVG graphics |
| `elm/markdown` | Low | Markdown rendering |

---

## Recommended Architecture: Separate Monorepo with Submodule Integration

### Option Comparison

| Approach | Pros | Cons |
|----------|------|------|
| **Monorepo (current)** | Simple, atomic changes, shared CI | Version coupling, large repo, harder for external contributors |
| **Separate repos per package** | Independent versions, clear ownership | Coordination nightmare, cross-package changes painful |
| **Separate monorepo + submodule** | Independent versions, unified workflow, easy local dev | Slight complexity with submodule management |

### Recommended Structure

```
~/fh/
├── canopy/                          # Compiler repo (current)
│   ├── packages/
│   │   ├── canopy-core/             # Compiler core
│   │   ├── canopy-builder/          # Build system
│   │   └── canopy-terminal/         # CLI
│   ├── examples/                    # FFI examples
│   ├── docs/
│   ├── canopy-packages/             # GIT SUBMODULE
│   └── ...
│
└── canopy-packages/                 # NEW: Packages monorepo (separate repo)
    ├── packages/
    │   ├── core/                    # canopy/core
    │   │   ├── src/
    │   │   ├── test/
    │   │   ├── canopy.json
    │   │   ├── CHANGELOG.md
    │   │   └── README.md
    │   ├── browser/                 # canopy/browser
    │   ├── html/                    # canopy/html
    │   ├── virtual-dom/             # canopy/virtual-dom
    │   ├── json/                    # canopy/json
    │   ├── url/                     # canopy/url
    │   ├── http/                    # canopy/http
    │   └── ...
    ├── scripts/
    │   ├── build-all.sh
    │   ├── test-all.sh
    │   └── publish.sh
    ├── CLAUDE.md                    # Package dev standards
    ├── CONTRIBUTING.md
    └── canopy-packages.json         # Workspace manifest
```

### Why This Architecture?

1. **Version Independence**: Packages can be released independently of the compiler
2. **Clear Boundaries**: Contributors know where to go for compiler vs package work
3. **Local Development**: Submodule in compiler repo for seamless local dev
4. **CI Isolation**: Package CI doesn't block compiler CI and vice versa
5. **Community Friendly**: Easier for external contributors to focus on packages
6. **Monorepo Benefits**: Cross-package refactoring, shared tooling, atomic commits within packages

---

## Implementation Plan

### Phase 1: Repository Setup (Week 1)

#### 1.1 Create the canopy-packages repository

```bash
# Create new repo
mkdir ~/fh/canopy-packages
cd ~/fh/canopy-packages
git init

# Create structure
mkdir -p packages/{core,browser,html,virtual-dom,json,url,http,time,random}
mkdir -p scripts
touch canopy-packages.json CLAUDE.md CONTRIBUTING.md
```

#### 1.2 Move existing packages

```bash
# From canopy repo
mv core-packages/core/* ~/fh/canopy-packages/packages/core/
mv core-packages/test/* ~/fh/canopy-packages/packages/test/
mv core-packages/debug/* ~/fh/canopy-packages/packages/debug/

# Keep symlinks for backwards compatibility during transition
ln -s ../canopy-packages/packages core-packages
```

#### 1.3 Add as submodule to compiler repo

```bash
cd ~/fh/canopy
git submodule add ../canopy-packages canopy-packages
git submodule update --init --recursive
```

### Phase 2: Workspace Configuration (Week 1-2)

#### canopy-packages.json (workspace manifest)

```json
{
  "name": "canopy-packages",
  "version": "0.1.0",
  "description": "Official Canopy standard library packages",
  "packages": [
    "packages/core",
    "packages/browser",
    "packages/html",
    "packages/virtual-dom",
    "packages/json",
    "packages/url",
    "packages/http",
    "packages/time",
    "packages/random",
    "packages/test",
    "packages/debug"
  ],
  "canopy-compiler-version": "0.19.1",
  "registry": "https://registry.canopy.dev"
}
```

#### Package dependency graph

```
                    ┌─────────────┐
                    │ canopy/core │  (no dependencies)
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │canopy/json │  │canopy/time │  │canopy/random│
    └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
          │               │               │
          ▼               ▼               ▼
   ┌─────────────┐  ┌──────────────────────────┐
   │canopy/url   │  │    canopy/virtual-dom    │
   └─────┬───────┘  └────────────┬─────────────┘
         │                       │
         │          ┌────────────┴────────────┐
         │          │                         │
         ▼          ▼                         ▼
   ┌───────────────────┐              ┌────────────┐
   │  canopy/browser   │              │canopy/html │
   └───────────────────┘              └────────────┘
                  │
                  ▼
          ┌────────────┐
          │canopy/http │
          └────────────┘
```

### Phase 3: CI/CD Setup (Week 2)

#### GitHub Actions workflow for canopy-packages

```yaml
# .github/workflows/ci.yml
name: Package CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        package: [core, browser, html, json, url, http, time, random]

    steps:
      - uses: actions/checkout@v4

      - name: Setup Canopy Compiler
        uses: canopy-lang/setup-canopy@v1
        with:
          version: '0.19.1'

      - name: Build package
        run: |
          cd packages/${{ matrix.package }}
          canopy make --docs

      - name: Run tests
        run: |
          cd packages/${{ matrix.package }}
          canopy test

      - name: Check documentation
        run: |
          cd packages/${{ matrix.package }}
          canopy docs --validate
```

#### Compiler repo CI update

```yaml
# In canopy repo .github/workflows/ci.yml
jobs:
  build-with-packages:
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build compiler
        run: make build

      - name: Test with local packages
        run: |
          export CANOPY_PACKAGE_PATH=./canopy-packages/packages
          make test-integration
```

### Phase 4: Package Development Workflow (Week 2-3)

#### Local development setup script

```bash
#!/bin/bash
# scripts/dev-setup.sh

# Clone compiler with packages
git clone --recurse-submodules https://github.com/canopy-lang/canopy.git
cd canopy

# Or if already cloned:
git submodule update --init --recursive

# Build compiler
make build

# Link local packages for development
export CANOPY_PACKAGE_PATH=$(pwd)/canopy-packages/packages

# Test everything works
canopy make examples/math-ffi/src/Main.can
```

#### Package development workflow

```bash
# Work on a package
cd canopy-packages/packages/html

# Make changes to src/Html.can
vim src/Html.can

# Build and test the package
canopy make --docs
canopy test

# Test integration with compiler
cd ../../..  # back to canopy root
export CANOPY_PACKAGE_PATH=./canopy-packages/packages
canopy make examples/audio-ffi/src/Main.can

# Commit to packages repo
cd canopy-packages
git add -A
git commit -m "feat(html): add accessibility attributes"
git push

# Update submodule reference in compiler
cd ..
git add canopy-packages
git commit -m "chore: update packages submodule"
```

### Phase 5: Fork Elm Packages with FFI (Weeks 3-8)

#### Priority order for forking

1. **Week 3-4**: `canopy/virtual-dom`, `canopy/html` (foundation)
2. **Week 4-5**: `canopy/browser`, `canopy/url` (navigation)
3. **Week 5-6**: `canopy/json`, `canopy/http` (data handling)
4. **Week 6-7**: `canopy/time`, `canopy/random` (utilities)
5. **Week 7-8**: `canopy/file`, `canopy/bytes`, `canopy/parser` (advanced)

#### For each package

1. Create directory structure in canopy-packages
2. Copy Elm source files
3. Update module names (`Html` → `Html`, but package `canopy/html`)
4. Add FFI declarations where JavaScript interop needed
5. Write JSDoc-annotated JavaScript in `external/`
6. Update `canopy.json` manifest
7. Write tests
8. Update documentation

#### Example: Converting elm/json to canopy/json

```
packages/json/
├── src/
│   ├── Json/
│   │   ├── Decode.can
│   │   ├── Encode.can
│   │   └── Error.can
│   └── Json.can
├── external/
│   └── json.js           # FFI for native JSON parsing
├── test/
│   ├── DecodeTest.can
│   └── EncodeTest.can
├── canopy.json
├── CHANGELOG.md
└── README.md
```

---

## Version Management Strategy

### Semantic Versioning Rules

| Change Type | Version Bump | Example |
|-------------|--------------|---------|
| Bug fix, no API change | PATCH (0.0.x) | 1.0.0 → 1.0.1 |
| New function/type, backwards compatible | MINOR (0.x.0) | 1.0.0 → 1.1.0 |
| Breaking change | MAJOR (x.0.0) | 1.0.0 → 2.0.0 |

### Version Pinning in Compiler

The compiler's `canopy-packages.json` pins the minimum version:

```json
{
  "canopy-compiler-version": "0.19.1",
  "minimum-package-versions": {
    "canopy/core": "1.0.0",
    "canopy/browser": "1.0.0",
    "canopy/html": "1.0.0"
  }
}
```

### Release Process

```bash
# In canopy-packages repo
cd packages/html

# Update version in canopy.json
# Update CHANGELOG.md

# Tag release
git tag canopy-html-v1.1.0
git push --tags

# CI publishes to registry
```

---

## Alternative Approaches Considered

### A. Git Subtree (Rejected)

**Pros:** Simpler mental model, no submodule commands
**Cons:** History pollution, harder to contribute upstream, less standard

### B. npm/yarn workspaces style (Rejected)

**Pros:** Familiar to JS developers
**Cons:** Elm/Canopy has its own package format, adds unnecessary tooling

### C. Keep in compiler monorepo (Rejected)

**Pros:** Simplest, atomic commits
**Cons:** Version coupling, forces package releases with compiler, intimidating for package contributors

---

## Migration Checklist

- [ ] Create canopy-packages GitHub repository
- [ ] Move existing packages from core-packages/
- [ ] Set up submodule in compiler repo
- [ ] Create CI/CD pipelines for both repos
- [ ] Update compiler to support `CANOPY_PACKAGE_PATH` for local dev
- [ ] Document development workflow in CONTRIBUTING.md
- [ ] Fork and convert elm/virtual-dom
- [ ] Fork and convert elm/html
- [ ] Fork and convert elm/browser
- [ ] Fork and convert elm/json
- [ ] Fork and convert elm/url
- [ ] Fork and convert elm/http
- [ ] Set up package registry (canopy.dev)
- [ ] Announce to community

---

## Questions to Resolve

1. **Registry**: Will you host your own package registry at canopy.dev, or use Elm's registry with aliasing?

2. **Backwards compatibility**: How long to maintain elm/* symlinks?

3. **Community packages**: Will third-party packages also move to canopy-packages monorepo or stay independent?

4. **Kernel code**: How to handle Elm's kernel/effect manager code that requires special compiler privileges?

---

## References

- [Monorepo Best Practices](https://monorepo.tools/)
- [Git Subtree vs Submodule](https://www.atlassian.com/git/tutorials/git-subtree)
- [Elm GitHub Organization](https://github.com/elm)
- [Package Migration Visual Architecture](./PACKAGE_MIGRATION_VISUAL_ARCHITECTURE.md)
