# Plan 28: Authentication & Authorization Patterns

## Priority: MEDIUM — Tier 2
## Effort: 3-4 weeks
## Depends on: Plan 05 (CanopyKit), Plan 13 (capabilities)

## Problem

Every production app needs auth. There's no standard pattern in functional frontend languages. Teams reinvent OAuth flows, JWT handling, session management, and protected routes every time.

## Solution: Type-Safe Auth as a Library + CanopyKit Integration

### Session Types

```canopy
module Auth exposing (Session, Guest, Authenticated, withAuth)

{-| A session that tracks authentication state at the type level. -}
type Session
    = Guest
    | Authenticated AuthenticatedUser

type alias AuthenticatedUser =
    { id : UserId
    , email : Email
    , roles : Set Role
    , token : AccessToken
    , expiresAt : Posix
    }
```

### Protected Routes (CanopyKit)

```canopy
-- This page REQUIRES authentication. The compiler enforces it.
page =
    Page.protected
        { load = \session request ->
            -- `session` is guaranteed to be Authenticated here
            -- If the user is Guest, CanopyKit redirects to login automatically
            fetchDashboardData session.token
        , view = \session model ->
            viewDashboard session.user model
        }

-- This page allows guests:
page =
    Page.public
        { view = \maybeSession model ->
            -- maybeSession : Maybe AuthenticatedUser
            viewHomePage maybeSession model
        }
```

### Role-Based Access

```canopy
type Role = Admin | Editor | Viewer

-- Type-safe role checking:
page =
    Page.protected
        { requiredRoles = Set.fromList [ Admin, Editor ]
        , onUnauthorized = RedirectTo Routes.Home
        , load = ...
        , view = ...
        }

-- In views:
viewAdminPanel : AuthenticatedUser -> Html Msg
viewAdminPanel user =
    if Auth.hasRole Admin user then
        adminControls
    else
        text "You don't have permission to view this."
```

### OAuth Integration

```canopy
-- canopy.json
{
  "auth": {
    "providers": ["google", "github"],
    "sessionStorage": "cookie",
    "tokenRefresh": true
  }
}

-- Generated module:
module Auth.Providers exposing (loginWithGoogle, loginWithGithub, logout)

loginWithGoogle : Cmd Msg
loginWithGithub : Cmd Msg
logout : Cmd Msg
```

### JWT Handling

```canopy
-- Automatic token refresh:
Auth.configure
    { refreshThreshold = Minutes 5  -- refresh when < 5 min until expiry
    , onRefreshFail = ForceLogout
    , storage = Auth.Cookie { httpOnly = True, secure = True, sameSite = Strict }
    }
```

## Implementation

### Phase 1: Core auth types (Week 1)
- `Session`, `AuthenticatedUser`, `Role` types
- Token storage and refresh logic
- Session persistence (cookie/localStorage)

### Phase 2: CanopyKit integration (Weeks 2-3)
- `Page.protected` and `Page.public` route types
- Automatic redirect for unauthenticated access
- Role-based route guards
- Session middleware

### Phase 3: OAuth providers (Week 4)
- Google, GitHub, Apple OAuth flows
- PKCE flow implementation
- Token exchange server-side
- Configurable via canopy.json
