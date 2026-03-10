# Plan 29: Local-First & Sync Engine

## Priority: MEDIUM — Tier 3 (Differentiator)
## Effort: 8-10 weeks
## Depends on: Plan 08 (stores), Plan 16 (effects)

## Problem

The biggest architectural shift in frontend (2025-2026) is local-first: apps that work offline, sync in the background, and handle conflicts automatically. CRDTs (Yjs, Automerge), sync engines (PowerSync, TanStack DB), and offline-first patterns are becoming standard.

A pure functional language with immutable data structures is uniquely positioned to implement this well.

## Solution: Synced Stores with CRDT-Based Conflict Resolution

### Core API

```canopy
module Sync exposing (Synced, synced, offline, conflict)

{-| A store that syncs with a remote source. Works offline.
    Conflicts are resolved automatically via CRDT merge.
-}
type Synced a

{-| Create a synced store with a server endpoint. -}
synced :
    { endpoint : String
    , initial : a
    , merge : a -> a -> a  -- conflict resolution
    }
    -> Synced a
```

### Usage

```canopy
-- Define a synced document:
sharedDocument : Synced Document
sharedDocument =
    Sync.synced
        { endpoint = "/api/documents/123"
        , initial = Document.empty
        , merge = Document.merge  -- CRDT merge function
        }

-- Read (always instant, from local state):
view model =
    case Sync.read sharedDocument model.syncState of
        { data, syncStatus } ->
            div []
                [ viewDocument data
                , viewSyncStatus syncStatus  -- Online | Syncing | Offline | Conflict
                ]

-- Write (instant local update, background sync):
update msg model =
    case msg of
        UserTyped newText ->
            ( model
            , Sync.update sharedDocument
                (\doc -> { doc | content = newText })
            )
```

### Offline Support

```canopy
-- The Synced store automatically:
-- 1. Applies mutations locally (instant UI update)
-- 2. Queues mutations for sync
-- 3. Syncs when online
-- 4. Persists queue to IndexedDB for durability across page reloads
-- 5. Resolves conflicts on reconnection using the merge function

-- Developers see none of this plumbing. It's all handled by the runtime.
```

### Presence (Who's Online)

```canopy
-- Track connected users:
presence : Sync.Presence UserInfo
presence =
    Sync.presence
        { endpoint = "/api/presence"
        , self = { name = model.user.name, cursor = model.cursor }
        }

-- Read in view:
viewCollaborators model =
    Sync.readPresence presence model.syncState
        |> List.map (\{ name, cursor } ->
            viewUserCursor name cursor
        )
```

## Implementation

This is a runtime library, not a compiler feature. But it leverages Canopy's immutability guarantees for safe concurrent merges.

### Phase 1: Local store with offline queue (Weeks 1-3)
- IndexedDB persistence layer
- Mutation queue with retry
- Online/offline detection
- Basic merge (last-write-wins)

### Phase 2: CRDT integration (Weeks 4-6)
- Pluggable CRDT merge strategies
- Text CRDT for collaborative editing (Yjs integration via FFI)
- Counter, Set, Map CRDTs for structured data

### Phase 3: Real-time sync (Weeks 7-8)
- WebSocket-based sync protocol
- Presence tracking
- Typing indicators
- Optimistic mutations with rollback

### Phase 4: Server adapter (Weeks 9-10)
- CanopyKit server middleware for sync endpoints
- Conflict resolution on server
- Persistence to database
