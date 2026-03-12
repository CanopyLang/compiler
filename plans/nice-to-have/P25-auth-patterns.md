# Plan 25: Authentication and Authorization Patterns

## Priority: LOW -- Tier 4
## Status: ~70% complete
## Effort: 1-2 weeks (revised down from 3-4 -- auth library already exists)
## Depends on: Plan 05 (CanopyKit), Plan 13 (capabilities)

## What Already Exists

### Auth Library (`canopy/auth` -- 5 files)
- **Session.can**: Session management (create, read, destroy, persistence to cookie/localStorage)
- **Token.can**: JWT handling (decode, verify, refresh, expiration tracking)
- **OAuth.can**: OAuth2 flows (authorization code + PKCE, token exchange)
- **Provider.can**: Provider configuration (Google, GitHub, Apple)
- **Guard.can**: Route guards (check authentication status, role verification)

### Related Infrastructure
- `canopy/router` (4 files) -- route definitions and navigation
- `canopy/browser` (5 files) -- cookie access, localStorage
- `canopy/web-crypto` -- cryptographic operations for token verification
- Capability system for enforcing auth requirements at compile time

## What Remains

### Phase 1: CanopyKit Integration (Week 1)
- `Page.protected` route type: compiler enforces that the session is `Authenticated`
  ```canopy
  page =
      Page.protected
          { load = \session request ->
              -- session is guaranteed Authenticated here
              -- Guest users are redirected to login automatically
              fetchDashboardData session.token
          , view = \session model ->
              viewDashboard session.user model
          }
  ```
- `Page.public` route type: receives `Maybe AuthenticatedUser`
- Automatic redirect-to-login for unauthenticated access to protected pages
- Session middleware in CanopyKit server pipeline

### Phase 2: Role-Based Access Types (Week 2)
- Type-safe role definitions:
  ```canopy
  type Role = Admin | Editor | Viewer

  page =
      Page.protected
          { requiredRoles = Set.fromList [ Admin, Editor ]
          , onUnauthorized = RedirectTo Routes.Home
          , load = ...
          , view = ...
          }
  ```
- Compile-time verification that role checks are exhaustive
- View-level role guards (`Auth.hasRole Admin user`)
- API endpoint authorization middleware for CanopyKit

## Architecture

The existing `canopy/auth` package handles the heavy lifting:

```
┌──────────────────────────────────────────┐
│  canopy/auth (EXISTS)                    │
│                                          │
│  Session.can ── session lifecycle        │
│  Token.can ──── JWT decode/verify/refresh│
│  OAuth.can ──── OAuth2 + PKCE flows      │
│  Provider.can ─ Google/GitHub/Apple      │
│  Guard.can ──── route guards             │
└──────────────┬───────────────────────────┘
               │
               ▼  Integration needed
┌──────────────────────────────────────────┐
│  CanopyKit (REMAINING WORK)              │
│                                          │
│  Page.protected / Page.public            │
│  Session middleware                      │
│  Role-based route guards                 │
│  Automatic login redirects              │
└──────────────────────────────────────────┘
```

## Definition of Done

- [ ] `Page.protected` enforces authentication at the type level
- [ ] `Page.public` provides optional session access
- [ ] Role-based access control with compile-time checks
- [ ] Automatic redirect to login for unauthenticated access
- [ ] Session middleware in CanopyKit server pipeline
- [ ] Documentation with examples for common auth patterns

## Risks

- **Token storage security**: Must default to httpOnly secure cookies. localStorage tokens are vulnerable to XSS.
- **OAuth complexity**: Each provider has quirks. The existing `canopy/auth` Provider module handles this, but edge cases will surface.
- **Session expiration UX**: Token refresh failures must be handled gracefully (redirect to login, preserve navigation state).
