# Plan 17: Effect Annotations (Simplified Algebraic Effects)

## Priority: MEDIUM — Tier 3
## Status: 0% complete (design only, no compiler work started)
## Effort: 6-8 weeks (reduced from 10-14 by shipping annotations-first)
## Depends on: Stable compiler (Tiers 0-1)

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| `Cmd msg` / `Sub msg` | `canopy/core` | COMPLETE — opaque effect types (inherited from Elm) |
| Ability system | P06 | COMPLETE — trait-like type classes, but not effect tracking |
| Type inference | `Type/` | COMPLETE — Hindley-Milner with extensions |
| Row types for records | `Type/` | COMPLETE — extensible record types |

Nothing exists at the compiler level for effect tracking. The current `Cmd msg` and `Sub msg` types are opaque — you cannot tell from a function's type whether it performs HTTP requests, reads storage, generates random numbers, or does nothing.

The P06 ability system provides the trait/typeclass mechanism but does not track effects. Effects require a different kind of type-level tracking: row-polymorphic effect sets on function types.

## What Remains

### Phase 1: Effect Inference and Display (Weeks 1-4)

The compiler infers which effects each function uses and displays them without requiring developers to annotate anything.

- Add effect type variables to the type system (extending the existing row type machinery used for records)
- Modify type inference to propagate effects through function calls
- Effects compose via row polymorphism: `{ Http, Storage | r }` means "at least Http and Storage, possibly more"
- Display inferred effects in LSP hover, error messages, and `canopy build --verbose` output

```canopy
-- The compiler infers: { Http, Time } Task ApiError Dashboard
-- but developers do NOT need to write this annotation
loadDashboard =
    Task.map2 Dashboard
        (Http.get "/api/stats")
        Time.now
```

This phase delivers 80% of the value: developers can SEE what effects their code has. The compiler can use this information for SSR auto-splitting (functions without DOM effects can run on the server).

### Phase 2: Effect Declarations and Handlers (Weeks 5-8)

Full user-defined effect system:

- `effect` keyword for declaring effect interfaces
- `Handler` type for providing effect implementations
- `Task.run` for executing effectful computations with specific handlers
- Built-in effects for Http, Time, Random, Storage (replacing current `Cmd`/`Sub` wrappers)

```canopy
effect Http where
    get : String -> Task HttpError Response
    post : String -> Body -> Task HttpError Response

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

### Phase 3: SSR Auto-Splitting (Future, Deferred)

- The compiler uses effect information to automatically split server/client code
- Functions with only `Http` and `Storage` effects can run on the server
- Functions with `Dom` effects must run on the client
- CanopyKit uses this for automatic server components

Deferred until Phase 1 proves valuable and the type system stabilization is complete.

### Backward Compatibility

- All existing Canopy/Elm code continues to work unchanged
- `Cmd msg` becomes a type alias for `{ Platform } Task Never msg`
- `Sub msg` becomes a type alias for `{ Platform } Subscription msg`
- Effect annotations are optional — the compiler infers them
- Developers can adopt effects gradually, one module at a time

## Dependencies

- Type inference engine (`Type/Solve.hs`, `Type/Unify.hs`) — must be extended with effect row variables
- Row type machinery — already exists for records, needs generalization to effects
- LSP — hover provider must display inferred effects
- CanopyKit — SSR auto-splitting consumes effect information (Phase 3)

## Risks

- **Type system complexity**: Adding row-polymorphic effects to Hindley-Milner inference is well-studied (Koka, Links, Frank) but non-trivial. The unification algorithm must handle effect rows, including row variable unification and effect subsumption.
- **Error messages**: Effect type errors can be confusing. Must invest heavily in plain-language error messages that explain what went wrong and suggest fixes. Effect mismatches should say "this function uses Http, but you're calling it in a context that doesn't allow Http" rather than showing raw row type variables.
- **Performance**: Effect tracking adds information to every function type. Must ensure the type checker does not slow down significantly. Benchmark inference time on large projects.
- **Community learning curve**: Effects are unfamiliar to most web developers. Documentation must include a gradual introduction starting from "the compiler tells you what your code does" (Phase 1) before introducing "you can define your own effects" (Phase 2).
