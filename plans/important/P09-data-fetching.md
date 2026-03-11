# Plan 25: Data Fetching & Caching Layer

## Priority: HIGH — Tier 1
## Effort: 4-5 weeks
## Depends on: Plan 03 (packages — COMPLETE), Plan 05 (CanopyKit for SSR integration)

## Problem

TanStack Query changed what developers expect from data fetching:
- Automatic caching with configurable staleness
- Background refetching (stale-while-revalidate)
- Request deduplication
- Optimistic updates
- Pagination / infinite scroll
- Loading/error/success states enforced by the type system

Elm has none of this. Developers manually manage loading states, write custom caching, and handle deduplication by hand.

## Solution: Query — Compile-Time Verified Data Fetching

### Core API

```canopy
module Query exposing (Query, useQuery, useMutation, RemoteData)

{-| The state of a remote data request.
    The type system enforces handling all states — impossible to
    access data without handling loading and error cases.
-}
type RemoteData error value
    = NotAsked
    | Loading
    | Failure error
    | Success value

{-| Define a query with a typed key and fetcher. -}
type Query key error value

{-| Create a query. -}
query :
    { key : key
    , fetch : key -> Task error value
    , staleTime : Duration
    }
    -> Query key error value
```

### Usage

```canopy
-- Define queries:
userQuery : Query UserId ApiError User
userQuery =
    Query.query
        { key = identity
        , fetch = \userId -> Http.get ("/api/users/" ++ UserId.toString userId)
        , staleTime = Minutes 5
        }

postsQuery : Query () ApiError (List Post)
postsQuery =
    Query.query
        { key = \() -> ()
        , fetch = \_ -> Http.get "/api/posts"
        , staleTime = Minutes 1
        }

-- Use in views:
viewUser : UserId -> Store (Query.Cache ApiError User) -> Html Msg
viewUser userId cache =
    case Query.read userQuery userId cache of
        NotAsked ->
            text ""  -- never rendered, query auto-fetches

        Loading ->
            spinner []

        Failure err ->
            errorBanner (ApiError.toString err)

        Success user ->
            div []
                [ h2 [] [ text (User.fullName user) ]
                , p [] [ text user.bio ]
                ]
```

### Compile-Time Enforcement

The type system makes it **impossible** to render data without handling loading/error:

```canopy
-- This is a COMPILE ERROR:
viewUser userId cache =
    let user = Query.read userQuery userId cache  -- RemoteData, not User!
    in div [] [ text user.name ]  -- Can't access .name on RemoteData

-- You MUST pattern match on all states:
viewUser userId cache =
    case Query.read userQuery userId cache of
        NotAsked -> ...
        Loading -> ...
        Failure err -> ...
        Success user -> text user.name  -- Only here is `user` a User
```

### Mutations with Optimistic Updates

```canopy
updateUser : Mutation UserId UserUpdate ApiError User
updateUser =
    Query.mutation
        { mutate = \userId update ->
            Http.patch ("/api/users/" ++ UserId.toString userId) (encodeUpdate update)
        , onOptimistic = \userId update cache ->
            -- Immediately update the cache with expected result:
            Query.updateCache userQuery userId
                (\user -> { user | name = update.name }) cache
        , onSuccess = \userId _ _ cache ->
            -- Invalidate related queries:
            Query.invalidate postsQuery () cache
        , onError = \_ _ cache ->
            -- Optimistic update auto-rolled back
            cache
        }
```

### Pagination

```canopy
paginatedPosts : PaginatedQuery () ApiError (List Post)
paginatedPosts =
    Query.paginated
        { fetch = \page -> Http.get ("/api/posts?page=" ++ String.fromInt page)
        , staleTime = Minutes 5
        }

view model =
    case Query.readPaginated paginatedPosts model.queryCache of
        { data, hasNextPage, isFetchingNext } ->
            div []
                [ ul [] (List.map viewPost data)
                , if hasNextPage then
                    button [ onClick LoadMore ] [ text "Load more" ]
                  else
                    text ""
                , if isFetchingNext then
                    spinner []
                  else
                    text ""
                ]
```

### SSR Integration (CanopyKit)

Queries prefetch on the server and serialize into HTML:

```canopy
-- In a CanopyKit page:
page =
    Page.server
        { load = \request ->
            -- Prefetch queries on server:
            Query.prefetch userQuery (Request.param "userId" request)
        , view = \model ->
            -- Cache is already populated from server prefetch:
            viewUser model.userId model.queryCache
        }
```

The client receives pre-populated cache. No loading spinner on first render.

## Implementation

### Phase 1: Core query engine (Weeks 1-2)
- `RemoteData` type
- `Query` type with fetch + staleTime
- In-memory cache with time-based staleness
- Request deduplication (same key = same request)
- Background refetching on stale reads

### Phase 2: Mutations and optimistic updates (Week 3)
- `Mutation` type
- Optimistic cache updates
- Automatic rollback on error
- Cache invalidation

### Phase 3: Pagination and infinite scroll (Week 4)
- `PaginatedQuery` type
- Page tracking and cursor management
- Append/prepend page results

### Phase 4: SSR integration (Week 5)
- Server-side prefetch
- Cache serialization into HTML
- Client-side cache hydration
