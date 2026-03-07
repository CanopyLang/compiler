# Plan 22: Package Registry

## Priority: LOW — Tier 4
## Effort: 6-8 weeks
## Depends on: Plan 03 (packages — COMPLETE), stable compiler

## Problem

Elm has no private package support. The CLI can't upgrade or uninstall packages natively. The single public registry (package.elm-lang.org) is controlled by one person.

Enterprise teams REQUIRE private packages. Open-source projects REQUIRE a reliable public registry.

## Solution: Canopy Package Registry

### Public Registry: packages.canopy-lang.org

A self-hosted, open-source package registry.

**Features:**
- Package publishing with semantic versioning (enforced by compiler)
- Automatic API diff between versions
- Documentation generation from Haddock-style comments
- Search by name, keyword, type signature
- Dependency graph visualization
- Download statistics
- Security advisories

**API:**

```
GET    /api/packages                        — list all packages
GET    /api/packages/:author/:name          — package metadata
GET    /api/packages/:author/:name/:version — specific version
GET    /api/packages/:author/:name/:version/docs — documentation
POST   /api/packages/:author/:name          — publish new version
GET    /api/search?q=json+decode            — search
GET    /api/search?type=String -> Maybe Int  — search by type signature
```

### Private Registries

Organizations can host their own registry:

```json
// canopy.json
{
  "registries": {
    "public": "https://packages.canopy-lang.org",
    "internal": "https://canopy-registry.mycompany.com"
  },
  "dependencies": {
    "canopy/html": "1.0.0",
    "@mycompany/design-system": "3.2.1"
  }
}
```

The `@mycompany/` scope resolves against the internal registry. Unscoped packages resolve against the public registry.

### CLI Commands

```bash
canopy install canopy/html                  # Install from public registry
canopy install @mycompany/design-system     # Install from private registry
canopy uninstall canopy/json                # Remove a package
canopy upgrade                              # Upgrade all to latest compatible
canopy upgrade canopy/html                  # Upgrade specific package
canopy outdated                             # Show outdated packages
canopy publish                              # Publish to registry
canopy docs                                 # Generate and preview docs locally
canopy audit                                # Security audit of dependencies
```

### Package Format

```
my-package/
  canopy.json           — package metadata, dependencies, exposed modules
  src/
    MyModule.can        — source files
  tests/
    MyModuleTest.can    — tests (run during publish to verify)
  README.md             — displayed on registry
  CHANGELOG.md          — version history
  LICENSE               — required for publishing
```

### Semantic Versioning Enforcement

The compiler automatically determines the version bump based on API changes:

```bash
canopy bump
# Analyzing API changes since 2.1.0...
#
# MAJOR changes detected:
#   - Removed: MyModule.oldFunction
#   - Changed: MyModule.parse (String -> Result) to (String -> Result ParseError Value)
#
# Recommended version: 3.0.0
# Proceed? [y/n]
```

This already exists in the compiler (`canopy diff` and `canopy bump`). Wire it into the publish flow.

### Lock File

```json
// canopy-lock.json (auto-generated, committed to git)
{
  "lockfileVersion": 1,
  "dependencies": {
    "canopy/core": {
      "version": "1.0.5",
      "integrity": "sha256-abc123...",
      "resolved": "https://packages.canopy-lang.org/canopy/core/1.0.5.tar.gz"
    },
    "canopy/html": {
      "version": "1.0.0",
      "integrity": "sha256-def456...",
      "resolved": "https://packages.canopy-lang.org/canopy/html/1.0.0.tar.gz"
    }
  }
}
```

Ensures reproducible builds across machines and CI.

## Implementation Phases

### Phase 1: Lock file and basic CLI (Weeks 1-2)
- Lock file generation and resolution
- `canopy install`, `canopy uninstall`, `canopy upgrade`, `canopy outdated`
- Offline cache for downloaded packages

### Phase 2: Public registry server (Weeks 3-5)
- REST API for package CRUD
- Package storage (S3 or filesystem)
- Search index (SQLite or PostgreSQL)
- Documentation generation pipeline
- Web UI for browsing packages

### Phase 3: Private registry support (Week 6)
- Scoped packages (`@org/name`)
- Multiple registry resolution
- Authentication (API tokens)
- Access control (org membership)

### Phase 4: Security and polish (Weeks 7-8)
- `canopy audit` — check for known vulnerabilities
- Package signing (optional)
- Rate limiting and abuse prevention
- Mirror support for enterprise networks

## Risks

- **Hosting costs**: Package storage grows over time. Use content-addressed storage to deduplicate.
- **Uptime**: The registry must be reliable. Use CDN for package downloads, keep the API server simple.
- **Governance**: Define clear policies for package naming, disputes, security responses. Learn from npm's mistakes.
