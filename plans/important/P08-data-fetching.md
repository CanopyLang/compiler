# Plan 08: Data Fetching & Caching Layer

## Priority: HIGH -- Tier 1
## Effort: 2-3 weeks remaining (revised 2026-03-11, down from 4-5 weeks)
## Depends on: Plan 03 (packages -- COMPLETE), Plan 05 (CanopyKit for SSR integration)
## Completion: ~70%

---

## Status Summary (2026-03-11 deep audit)

The library layer is substantially complete. Four stdlib packages provide the core
data fetching primitives. What remains is framework-level integration (CanopyKit SSR
prefetch, DataLoader detection) and documentation.

### What EXISTS (verified via source inspection)

#### canopy/http (v2.0.0) -- HTTP client
- `src/Http.can` -- standard HTTP request API
- Tests in `tests/Test/Http.can`

#### canopy/http-data (v1.0.0, ~4,803 lines total) -- Data layer with caching
- `src/Data.can` (956 lines) -- Central cache with TEA integration, `fetch`/`get`/`refetch`/`prefetch`, stale-while-revalidate, garbage collection, subscription-based lifecycle
- `src/Data/Query.can` (311 lines) -- QueryKey, QueryConfig, CacheEntry, FetchStatus, RetryConfig with exponential backoff
- `src/Data/RemoteData.can` (420 lines) -- `NotAsked | Loading | Reloading a | Success a | Failure e` with map/andThen/withDefault
- `src/Data/Mutation.can` (220 lines) -- MutationConfig with optimistic updates, snapshot/rollback, onSuccess/onError cache updates, key invalidation
- `src/Data/Pagination.can` (321 lines) -- Cursor-based and offset-based pagination, hasNextPage/hasPreviousPage, append/prepend
- Tests: 5 test files (~2,575 lines) covering Query, RemoteData, Data, Mutation, Pagination

**This package implements the full TanStack Query equivalent:**
- Automatic caching with configurable stale time
- Background refetching (stale-while-revalidate via `Reloading` state)
- Subscriber-based garbage collection
- Optimistic mutations with automatic rollback on failure
- Cache invalidation by key prefix
- Retry with configurable backoff
- Pagination (cursor and offset)

#### canopy/query (v1.0.0, ~2,010 lines total) -- Higher-level query API
- `src/Query.can` (434 lines) -- Type-safe queries wrapping HTTP with caching config, `read`/`readWithDefault`, `withStaleTime`/`withRetry`/`withCacheKey`, `toTask` for composition
- `src/Query/RemoteData.can` (335 lines) -- RemoteData type (separate from http-data's version)
- `src/Query/Cache.can` (201 lines) -- Time-based cache with staleness checking
- `src/Query/Mutation.can` (275 lines) -- Mutation execution with cache updates
- `src/Query/Paginated.can` (606 lines) -- PaginatedQuery with page tracking
- `src/Query/Invalidation.can` (159 lines) -- Cache invalidation strategies

#### canopy/graphql (v1.0.0, ~2,620 lines total) -- GraphQL client
- `src/GraphQL.can` (60 lines) -- Top-level API
- `src/GraphQL/Request.can` (100 lines) -- GraphQL request building
- `src/GraphQL/Response.can` (196 lines) -- Response parsing with error handling
- `src/GraphQL/Cache.can` (138 lines) -- Normalized GraphQL cache
- `src/GraphQL/Batch.can` (54 lines) -- Request batching
- `src/GraphQL/Internal/Selection.can` (167 lines) -- Selection set building
- `src/GraphQL/Internal/Encode.can` (98 lines) -- Query encoding
- Tests: 7 test files (~1,807 lines)

### What does NOT work (verified)

1. **DataLoader detection is stubbed.** `Kit/DataLoader.hs` (121 lines) defines `DataLoader` type and `generateLoaderModule`, but `detectLoaders` always returns `[]`. It needs to parse route module exports to find `load` functions.

2. **No SSR prefetch integration.** The `canopy/ssr` package exists with `Ssr.can`, `Ssr/Render.can`, `Ssr/Stream.can`, etc., but there is no bridge between `canopy/http-data`'s cache and SSR rendering. Server-side prefetch needs to populate the cache before rendering and serialize it into the HTML payload for client hydration.

3. **No cache serialization for SSR.** `Data.Cache` stores values as `Json.Decode.Value` which is good for serialization, but no `encodeCacheToJson`/`decodeCacheFromJson` functions exist for transferring server cache to client.

4. **Two competing RemoteData types.** `canopy/http-data` has `Data.RemoteData` with 5 variants (including `Reloading`) and `canopy/query` has `Query.RemoteData` with 4 variants. These should be consolidated or at least have a documented migration path.

5. **No request deduplication.** Neither package deduplicates in-flight requests for the same key. If two components request the same data simultaneously, two HTTP requests fire.

6. **Documentation and examples sparse.** Library code has doc comments but no standalone guide, tutorial, or migration-from-Elm examples.

---

## Problem

TanStack Query changed what developers expect from data fetching: automatic caching, stale-while-revalidate, optimistic updates, and type-safe loading states. The Canopy stdlib now provides these primitives, but they are not integrated with the framework (CanopyKit) and lack SSR support.

## What the Original Plan Called For vs. What Exists

| Feature | Status | Package |
|---------|--------|---------|
| RemoteData type | DONE | canopy/http-data, canopy/query |
| Query type with fetch + staleTime | DONE | canopy/query |
| In-memory cache with staleness | DONE | canopy/http-data, canopy/query |
| Background refetching (stale-while-revalidate) | DONE | canopy/http-data (`Reloading` state) |
| Optimistic mutations with rollback | DONE | canopy/http-data |
| Cache invalidation (prefix + exact) | DONE | canopy/http-data |
| Retry with backoff | DONE | canopy/http-data, canopy/query |
| Pagination (cursor + offset) | DONE | canopy/http-data, canopy/query |
| GraphQL client with caching | DONE | canopy/graphql |
| Request deduplication | NOT DONE | -- |
| SSR prefetch | NOT DONE | -- |
| Cache serialization to HTML | NOT DONE | -- |
| Client cache hydration | NOT DONE | -- |
| DataLoader detection in CanopyKit | STUBBED | canopy-terminal Kit/DataLoader.hs |
| DevTools cache inspector | NOT DONE | -- |
| Documentation + examples | NOT DONE | -- |

---

## Remaining Work

### Phase 1: SSR cache bridge (1 week)

**Work needed:**
- Add `encodeCacheToJson : Cache -> Json.Encode.Value` and `decodeCacheFromJson : Json.Decode.Value -> Result Error Cache` to `canopy/http-data`
- Integrate with `canopy/ssr`: during server render, prefetched data populates the cache; after render, cache is serialized into a `<script>` tag in the HTML
- On client side, `initCacheFromJson` hydrates the cache from the serialized payload
- Eliminates loading spinners on first render for prefetched data

### Phase 2: DataLoader detection (3-5 days)

**Current state:** `Kit/DataLoader.hs` types and code generation exist. `detectLoaders` returns `[]`.

**Work needed:**
- Parse route module exports to find `load` function (check `Src.Module._exports` for a `load` name)
- Determine loader kind (StaticLoader vs DynamicLoader) based on type annotation or convention
- Wire detected loaders into CanopyKit's route generation pipeline
- Test with sample route modules

### Phase 3: Request deduplication (3 days)

**Work needed:**
- Track in-flight requests by key in the cache
- When a second `fetch` for the same key arrives while one is in-flight, subscribe to the existing request instead of firing a new one
- Clear in-flight tracking on success/failure

### Phase 4: Consolidate RemoteData types (2 days)

**Work needed:**
- Decide canonical location: `canopy/http-data` has 5-variant version (`Reloading`), `canopy/query` has 4-variant version
- Either merge or document the relationship
- Consider re-exporting from one to the other

### Phase 5: Documentation and examples (3-5 days)

**Work needed:**
- Getting started guide for data fetching
- Migration guide from manual Elm HTTP to canopy/query
- Example: CRUD app with queries + mutations
- Example: Paginated list with infinite scroll
- Example: SSR with prefetched data
- Example: GraphQL usage

---

## Performance Targets

| Scenario | Target |
|----------|--------|
| Cache read (fresh) | < 1ms |
| Cache read (stale, triggers background refetch) | < 1ms (returns stale data immediately) |
| Optimistic mutation + rollback | < 5ms |
| SSR cache hydration (100 entries) | < 10ms |

## Key Files

```
# Stdlib packages (Canopy source)
packages/canopy/http/src/Http.can                    -- HTTP client
packages/canopy/http-data/src/Data.can               -- Central cache (956 lines)
packages/canopy/http-data/src/Data/Query.can         -- Query config + cache entry
packages/canopy/http-data/src/Data/RemoteData.can    -- RemoteData (5 variants)
packages/canopy/http-data/src/Data/Mutation.can      -- Mutations + optimistic updates
packages/canopy/http-data/src/Data/Pagination.can    -- Pagination helpers
packages/canopy/query/src/Query.can                  -- High-level query API (434 lines)
packages/canopy/query/src/Query/Cache.can            -- Time-based cache
packages/canopy/query/src/Query/Paginated.can        -- Paginated queries
packages/canopy/graphql/src/GraphQL.can              -- GraphQL client
packages/canopy/ssr/src/Ssr.can                      -- SSR rendering

# Compiler (Haskell)
packages/canopy-terminal/src/Kit/DataLoader.hs       -- DataLoader detection (STUBBED)
```
