# Plan 19: Package Registry

## Priority: LOW -- Tier 4
## Status: ~60% complete
## Effort: 3-4 weeks (revised down from 6-8 -- backend server already exists)
## Depends on: Plan 03 (packages -- COMPLETE), stable compiler

## What Already Exists

The package registry server is **already built** at `~/projects/canopy/server/`.

### Backend Server (Haskell/Yesod -- COMPLETE)
- **Framework**: Yesod web application with PostgreSQL + Redis
- **Handlers**: Package publishing, browsing, search, comments, user profiles, API keys
- **Infrastructure**: Docker support (Dockerfile, docker-compose.yml)
- **Admin**: Admin panel for moderation and management
- **Security**: Rate limiting, security validation, abuse prevention
- **Auth**: User authentication and API key management

### CLI Integration (COMPLETE)
- `canopy install`, `canopy uninstall`, `canopy upgrade`, `canopy outdated` -- all implemented
- Lock file generation and resolution
- Offline cache for downloaded packages
- `canopy diff` and `canopy bump` for semantic versioning enforcement

### Package Format (COMPLETE)
- `canopy.json` metadata, dependencies, exposed modules
- Semantic versioning enforced by compiler
- Automatic API diff between versions

## What Remains

### Phase 1: Frontend Portal (Weeks 1-2)
- Web UI for browsing packages (the server has API endpoints but no frontend)
- Search by name, keyword, type signature
- Package detail pages with documentation, README, version history
- Dependency graph visualization
- Download statistics dashboard

### Phase 2: CDN Integration (Week 3)
- CDN layer for package downloads (reduce server load)
- Content-addressed storage for deduplication
- Mirror support for enterprise networks behind firewalls
- Integrity hashes in lock files verified against CDN

### Phase 3: Private Scopes and API Documentation (Week 4)
- Scoped packages (`@org/name`) resolving against private registries
- Multiple registry resolution in `canopy.json`:
  ```json
  {
    "registries": {
      "public": "https://packages.canopy-lang.org",
      "internal": "https://canopy-registry.mycompany.com"
    }
  }
  ```
- Access control (org membership, team permissions)
- OpenAPI documentation for the registry REST API
- Self-hosting guide for organizations running private registries

## Architecture (Existing)

```
┌─────────────────────────────┐
│     Registry Server         │
│     (Haskell/Yesod)         │
│                             │
│  PostgreSQL ─── Handlers    │
│  Redis ──────── Cache       │
│  Docker ─────── Deployment  │
│                             │
│  Endpoints:                 │
│    /api/packages            │
│    /api/search              │
│    /api/publish             │
│    /api/users               │
│    /api/comments            │
│    /admin/*                 │
└─────────────────────────────┘
```

## Risks

- **Hosting costs**: Package storage grows over time. CDN and content-addressed storage mitigate this.
- **Uptime**: The registry must be reliable. CDN for package downloads keeps the API server load low.
- **Governance**: Clear policies needed for package naming, disputes, security responses.
