# Plan 24: Local-First and Sync Engine

## Priority: LOW -- Tier 4
## Status: ~25% complete
## Effort: 6-8 weeks (revised down from 8-10 -- storage and networking layers already exist)
## Depends on: Plan 08 (stores), Plan 16 (effects)

## What Already Exists

### IndexedDB Persistence (`canopy/indexed-db` -- 7 files)
- Schema versioning and migrations
- Type-safe read/write operations
- Transaction management
- Object store CRUD with cursors and indexes

### WebSocket with Reconnection (`canopy/websocket` -- 4 files)
- WebSocket connection management
- Automatic reconnection with backoff
- Message encoding/decoding
- Connection state tracking (connected, disconnected, reconnecting)

### Related Infrastructure
- `canopy/streams` -- streaming data processing
- `canopy/browser` (5 files) -- online/offline detection, visibility API
- Immutable data structures in Canopy make concurrent merges safe by design

## What Remains

### Phase 1: Offline Queue and Local Store (Weeks 1-2)
- Mutation queue backed by `canopy/indexed-db` for durability across page reloads
- Online/offline detection via `canopy/browser`
- Local-first read path: always read from local state (instant UI)
- Write path: apply locally, queue for sync
- Basic merge strategy: last-write-wins

### Phase 2: CRDT Integration (Weeks 3-5)
- Pluggable CRDT merge strategies
- Counter, Set, Map CRDTs for structured data
- Text CRDT for collaborative editing (Yjs integration via FFI)
- Canopy type-class-like interface for custom merge functions:
  ```canopy
  synced :
      { endpoint : String
      , initial : a
      , merge : a -> a -> a
      }
      -> Synced a
  ```

### Phase 3: Real-Time Sync Protocol (Weeks 6-7)
- Sync protocol over `canopy/websocket` (reconnection handled automatically)
- Presence tracking (who's online, cursor positions)
- Typing indicators
- Optimistic mutations with server-confirmed rollback

### Phase 4: Server Adapter (Week 8)
- CanopyKit server middleware for sync endpoints
- Conflict resolution on server side
- Persistence to database (PostgreSQL adapter)
- Admin dashboard for sync status monitoring

## API Design

```canopy
-- Define a synced store:
sharedDocument : Synced Document
sharedDocument =
    Sync.synced
        { endpoint = "/api/documents/123"
        , initial = Document.empty
        , merge = Document.merge
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

## Risks

- **CRDT complexity**: CRDTs are notoriously hard to implement correctly. Consider wrapping proven libraries (Yjs, Automerge) via FFI rather than building from scratch.
- **Conflict UX**: Automatic merge is not always what users want. Must provide escape hatches for manual conflict resolution.
- **Storage limits**: IndexedDB has browser-dependent storage quotas. Must handle quota exceeded errors gracefully.
- **Sync protocol design**: Getting the sync protocol right (ordering, deduplication, idempotency) is hard. Start simple with last-write-wins, iterate toward CRDTs.
