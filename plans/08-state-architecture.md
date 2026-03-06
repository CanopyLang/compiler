# Plan 08: State Architecture Beyond TEA

## Priority: HIGH — Tier 1
## Effort: 4-5 weeks
## Depends on: Plan 03 (packages)

## Problem

The Elm Architecture (TEA) works beautifully for small apps. At scale, it breaks:

1. **Single Model bottleneck**: All state flows through one Model. Parent components must manage all children's state. Wiring through every level creates noise.
2. **No code splitting**: TEA has no story for lazy-loading routes. Apps can take 20+ seconds to first load.
3. **Message indirection**: Tracing message flow through delegation layers becomes "really hard" at scale.
4. **System plumbing pollution**: HTTP responses, WebSocket messages, timers all become top-level message types.
5. **No encapsulated components**: Third-party components cannot manage their own state.

Production data from Redux/Zustand/Jotai shows the solution:

| Pattern | Avg Render Time |
|---------|----------------|
| Single monolithic store | 350ms |
| Domain-split stores | 32ms |
| Fine-grained selectors | 18ms |

## Solution: Keep TEA, Add Stores

TEA remains the primary architecture. We add **Stores** as an orthogonal state primitive for cases where TEA's single model is a bottleneck.

### Core API

```canopy
module Store exposing (Store, create, read, update, subscribe)

{-| A typed, reactive state container. Independent of TEA.
    Stores are created at the application level and passed to
    components that need them.
-}
type Store state

{-| Create a store with an initial value. -}
create : state -> Store state

{-| Read the current value. Pure, synchronous. -}
read : Store state -> state

{-| Update the store. Returns a Cmd that performs the update. -}
update : (state -> state) -> Store state -> Cmd msg

{-| Subscribe to changes. The subscription fires when the store updates. -}
subscribe : (state -> msg) -> Store state -> Sub msg
```

### Usage Pattern

```canopy
-- App.can (top level)
type alias Model =
    { userStore : Store User
    , cartStore : Store Cart
    , page : Page
    }

init =
    ( { userStore = Store.create Guest
      , cartStore = Store.create emptyCart
      , page = Home
      }
    , Cmd.none
    )

-- Components receive stores they need, NOT the whole model:
viewHeader : Store User -> Store Cart -> Html Msg
viewHeader userStore cartStore =
    let
        user = Store.read userStore
        cart = Store.read cartStore
    in
    nav []
        [ viewUserMenu user
        , viewCartBadge (Cart.itemCount cart)
        ]
```

### Fine-Grained Subscriptions

Components subscribe to specific stores, not the whole model:

```canopy
subscriptions model =
    Sub.batch
        [ Store.subscribe UserUpdated model.userStore
        , Store.subscribe CartUpdated model.cartStore
        -- viewHeader only re-renders when user or cart changes
        -- NOT when page navigation happens
        ]
```

### Selectors (Derived State)

```canopy
module Store.Selector exposing (Selector, select, map)

{-| A derived view of a store. Only recomputes when the source changes. -}
type Selector source derived

select : (source -> derived) -> Store source -> Selector source derived

-- Example: derive cart total from cart store
cartTotal : Store Cart -> Selector Cart Float
cartTotal =
    Store.Selector.select Cart.total
```

### Domain Stores Pattern

For large applications, split state by domain:

```
src/
  Stores/
    User.can        -- Store User (auth, profile, preferences)
    Cart.can        -- Store Cart (items, quantities, pricing)
    Notifications.can -- Store (List Notification)
    Theme.can       -- Store Theme (dark/light, colors)
```

Each store is independent. No global wiring. Components import only the stores they need.

## Implementation

### Compiler Support

Stores are implemented as a compiler-supported type that:

1. Holds mutable state internally (managed by the runtime, not exposed to user code)
2. Tracks subscribers (components that depend on this store)
3. Triggers targeted re-renders when updated (only subscribers, not the whole app)

The key insight: the compiler knows which stores each component reads. It can generate update code that only re-renders affected components.

### Runtime

The Store runtime is a thin layer:

```javascript
// canopy-runtime/store.js
export function create(initial) {
  let state = initial;
  const subscribers = new Set();
  return {
    _read() { return state; },
    _update(fn) { state = fn(state); subscribers.forEach(s => s(state)); },
    _subscribe(callback) { subscribers.add(callback); return () => subscribers.delete(callback); }
  };
}
```

### Integration with TEA

Stores are NOT a replacement for TEA. They work alongside it:

- **TEA** handles: page-level state, navigation, user interactions, command orchestration
- **Stores** handle: shared state across components, domain data, cached server data, UI preferences

The `update` function can still be the single source of truth for complex state transitions. Stores handle the cross-cutting data that TEA forces you to wire through every component.

### Integration with Plan 04 (Reactive Compiler)

When the reactive compiler (Plan 04) detects that a view reads from a Store, it generates a targeted subscription:

```javascript
// Generated: viewHeader only re-renders when userStore or cartStore changes
Store._subscribe(userStore, () => _updateHeader(handles));
Store._subscribe(cartStore, () => _updateHeader(handles));
```

This is the fine-grained reactivity path for cross-component state.

## Migration Path

TEA is not deprecated. Existing apps continue to work. Stores are opt-in:

1. Identify state that's shared across many components
2. Extract it into a Store
3. Replace model threading with store reads
4. Add subscriptions for reactive updates

## Risks

- **Mutable state behind the scenes**: Stores hold mutable state internally. This is hidden from the developer (they see pure reads and Cmd-based updates), but it's a departure from Elm's everything-is-immutable philosophy. Mitigation: stores are owned by the runtime, not user code. Updates go through the TEA command pipeline.
- **Potential for spaghetti**: Too many stores with complex interdependencies could create the same problems as React context. Mitigation: documentation and patterns for when to use stores vs TEA.
