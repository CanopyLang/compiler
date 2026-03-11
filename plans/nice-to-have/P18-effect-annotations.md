# Plan 16: Effect Annotations (Simplified Algebraic Effects)

## Priority: MEDIUM — Tier 3
## Effort: 6-8 weeks (reduced from 10-14 by shipping annotations-first)
## Depends on: Stable compiler (Tiers 0-1)

> **Note (revised):** The full algebraic effects system (effect declarations, handlers,
> row-polymorphic composition) is research-grade work requiring 10-14 weeks. A simpler
> first step delivers 80% of the value: **inferred effect annotations** that the compiler
> tracks and displays, without full user-defined handlers.
>
> Phase 1 (6-8 weeks): The compiler infers which effects each function uses and displays
> them in LSP hover, error messages, and `canopy build` output. This enables SSR auto-splitting
> (functions without DOM effects can run on the server) and better documentation.
>
> Phase 2 (future): Full effect handlers, `effect` declarations, and testing with mock handlers.
> Deferred until Phase 1 proves valuable and the type system stabilization is complete.

## Problem

Canopy (like Elm) uses `Cmd msg` and `Sub msg` for side effects. These are opaque — you can't see from a function's type what effects it performs. `Cmd msg` could be an HTTP request, a random number, a file write, or nothing at all.

This prevents:
- **Testing**: Can't swap real HTTP for mock HTTP without ports
- **Reasoning**: Can't know if a function touches the network just from its type
- **Composition**: Can't combine Cmd producers without wrapping in custom types
- **SSR optimization**: Can't automatically determine server/client split

Algebraic effects (as in Koka, OCaml 5) solve all of these.

## Solution

### Effect Declarations

```canopy
-- Declare an effect with its operations:
effect Http where
    get : String -> Task HttpError Response
    post : String -> Body -> Task HttpError Response

effect Time where
    now : Task Never Posix
    every : Float -> (Posix -> msg) -> Sub msg

effect Random where
    generate : Generator a -> Task Never a

effect Storage where
    getItem : String -> Task StorageError (Maybe String)
    setItem : String -> String -> Task StorageError ()
```

### Effect Types in Signatures

```canopy
-- Function types show which effects they use:
fetchUser : String -> { Http } Task ApiError User
fetchUser userId =
    Http.get ("/api/users/" ++ userId)
        |> Task.andThen decodeUser

-- Multiple effects compose naturally:
fetchAndCache : String -> { Http, Storage } Task AppError User
fetchAndCache userId =
    fetchUser userId
        |> Task.andThen (\user ->
            Storage.setItem ("user:" ++ userId) (encodeUser user)
                |> Task.map (\_ -> user)
        )

-- Pure functions have no effects:
formatName : User -> String  -- no effect annotation = pure
```

### Effect Handlers

```canopy
-- Production handler (real HTTP):
httpHandler : Handler Http
httpHandler =
    Http.handler
        { get = \url -> XmlHttpRequest.get url
        , post = \url body -> XmlHttpRequest.post url body
        }

-- Test handler (mock HTTP):
mockHttpHandler : List (String, Response) -> Handler Http
mockHttpHandler responses =
    Http.handler
        { get = \url ->
            List.find (\(u, _) -> u == url) responses
                |> Maybe.map Tuple.second
                |> Maybe.withDefault (Response.error 404)
                |> Task.succeed
        , post = \_ _ -> Task.succeed (Response.ok "")
        }
```

### Testing with Effects

```canopy
-- Test that fetchUser calls the right endpoint:
testFetchUser =
    test "fetchUser calls /api/users/:id" <|
        \() ->
            fetchUser "123"
                |> Task.run (mockHttpHandler
                    [ ("/api/users/123", Response.ok userJson) ]
                  )
                |> Expect.equal (Ok expectedUser)
```

No ports needed. No test infrastructure. Just swap the handler.

### Effect Composition

Effects compose via row polymorphism:

```canopy
-- This function works with any effect set that includes Http:
withRetry : { Http | r } Task e a -> { Http | r } Task e a
withRetry task =
    task
        |> Task.onError (\_ -> Task.sleep 1000 |> Task.andThen (\_ -> task))

-- It doesn't care what other effects are present:
fetchAndCacheWithRetry : { Http, Storage } Task AppError User
fetchAndCacheWithRetry userId =
    withRetry (fetchAndCache userId)
```

### Effect Inference

The compiler infers effects automatically. Developers don't need to write effect annotations unless they want to:

```canopy
-- The compiler infers: { Http, Time } Task ApiError Dashboard
loadDashboard =
    Task.map2 Dashboard
        (Http.get "/api/stats")
        Time.now
```

## Implementation

### Phase 1: Effect tracking (Weeks 1-4)
- Add effect type variables to the type system
- Modify type inference to track effects through function calls
- Effects compose via row polymorphism (similar to existing record row types)
- Display inferred effects in hover information

### Phase 2: Effect declarations and handlers (Weeks 5-8)
- `effect` keyword for declaring effect interfaces
- `Handler` type for providing implementations
- `Task.run` for executing effectful computations with specific handlers
- Built-in effects for Http, Time, Random, Storage (replacing current Cmd/Sub)

### Phase 3: Migration and compatibility (Weeks 9-10)
- `Cmd msg` becomes a type alias for `{ Platform } Task Never msg`
- `Sub msg` becomes a type alias for `{ Platform } Subscription msg`
- Existing code continues to work — effects are inferred, not required
- New code can opt into explicit effect annotations

### Phase 4: SSR optimization (Weeks 11-14)
- The compiler uses effect information to automatically split server/client code
- Functions with only `Http` and `Storage` effects can run on the server
- Functions with `Dom` effects must run on the client
- CanopyKit uses this for automatic server components

## Backward Compatibility

- All existing Canopy/Elm code continues to work unchanged
- `Cmd` and `Sub` become type aliases — zero migration needed
- Effect annotations are optional — the compiler infers them
- Developers can adopt effects gradually, one module at a time

## Risks

- **Type system complexity**: Adding row-polymorphic effects to Hindley-Milner inference is well-studied (Koka, Links) but non-trivial. The unification algorithm must handle effect rows.
- **Error messages**: Effect type errors can be confusing. Must invest in clear error messages that explain in plain language what went wrong.
- **Performance**: Effect tracking adds information to every function type. Must ensure the type checker doesn't slow down significantly.
- **Community learning curve**: Effects are unfamiliar to most web developers. Documentation must include many examples and a gradual introduction.

## Why This Matters

Effects are the feature that makes Canopy categorically different from every other frontend technology:

- **React**: No way to know what side effects a component has. UseEffect can do anything.
- **Angular**: Services can have any dependency. No compile-time tracking.
- **Vue**: Composition API functions can call any API. No visibility.
- **Svelte**: `$effect` blocks can contain anything.
- **Canopy with effects**: `{ Http, Storage } Task Error User` — you know EXACTLY what this function does. You can test it by swapping handlers. You can run it on the server because it doesn't touch the DOM.

This is the kind of guarantee that makes Canopy worth learning.
