# Plan 23: Animation & Motion System

## Priority: HIGH — Tier 1 (moved up from "nice-to-have")
## Effort: 4-6 weeks
## Depends on: Plan 03 (packages), Plan 04 (reactivity helps but not required)

## Problem

Animation is no longer optional UX polish — it's core user experience. Users expect:
- Page transitions (View Transitions API)
- Micro-interactions (hover, press, toggle)
- Layout animations (element resize, reorder)
- Scroll-driven effects (parallax, reveal-on-scroll)
- Spring physics (natural, interruptible motion)

No compile-to-JS functional language has a good animation story. Elm has `elm-animator` (community) but nothing built in. This is a massive gap.

## Solution: Declarative, Composable Animation Primitives

### Core Types

```canopy
module Canopy.Motion exposing
    ( Transition, Spring, Animation, Gesture
    , transition, spring, keyframes
    , onHover, onPress, onFocus
    , stagger, sequence, parallel
    )

{-| A transition between two states, compiled to CSS transitions where possible. -}
type Transition

{-| A spring-based animation with velocity and damping. -}
type Spring

{-| A keyframe animation sequence. -}
type Animation

{-| A gesture-driven animation (drag, swipe, pinch). -}
type Gesture
```

### Usage: CSS-First, JS-Fallback

```canopy
-- Simple transition (compiles to CSS transition):
button
    [ css
        [ backgroundColor (Hex "#336699")
        , transition [ backgroundColor (Ms 200) EaseOut ]
        ]
    , css_hover [ backgroundColor (Hex "#264d73") ]
    , onClick DoSomething
    ]
    [ text "Click me" ]

-- Spring animation (JS-driven, interruptible):
div
    [ Motion.spring
        { property = Transform (TranslateX (Px 0))
        , to = Transform (TranslateX (Px (toFloat model.offset)))
        , stiffness = 300
        , damping = 30
        }
    ]
    [ content ]

-- Staggered list animation:
ul []
    (model.items
        |> List.indexedMap (\i item ->
            li
                [ Motion.stagger i
                    { enter = [ opacity 0, transform [ TranslateY (Px 20) ] ]
                    , to = [ opacity 1, transform [ TranslateY (Px 0) ] ]
                    , delay = Ms (i * 50)
                    }
                ]
                [ viewItem item ]
        )
    )
```

### View Transitions API Integration

Built into CanopyKit's router:

```canopy
-- Router automatically wraps page transitions in View Transitions API:
-- When navigating from /blog to /blog/post-1, the browser animates between pages.

-- Developer can customize per-component:
div [ viewTransitionName "hero-image" ]
    [ img "Blog hero" [ src model.heroUrl ] [] ]

-- The compiler generates unique view-transition-name attributes
-- and matching CSS for cross-page element transitions.
```

### Scroll-Driven Animations

```canopy
div
    [ Motion.onScroll
        { trigger = InView { threshold = 0.3 }
        , from = [ opacity 0, transform [ TranslateY (Px 30) ] ]
        , to = [ opacity 1, transform [ TranslateY (Px 0) ] ]
        }
    ]
    [ sectionContent ]
```

Compiles to CSS `scroll-timeline` and `animation-timeline` where browser-supported, falls back to IntersectionObserver.

### Gesture Handling

```canopy
-- Drag gesture:
div
    [ Motion.draggable
        { axis = Horizontal
        , onDrag = Dragging
        , onRelease = Released
        , constraints = { min = Px -200, max = Px 200 }
        }
    ]
    [ draggableContent ]
```

## Compiler Optimization

The compiler analyzes animations and chooses the best strategy:

1. **Static transitions** (hover, focus) → pure CSS (zero JS)
2. **Scroll-driven** → CSS scroll-timeline (zero JS where supported)
3. **Spring/physics** → requestAnimationFrame JS (minimal runtime)
4. **View transitions** → View Transitions API (browser-native)
5. **Gesture-driven** → Pointer events + requestAnimationFrame

## Implementation Phases

### Phase 1: CSS transitions and keyframes (Weeks 1-2)
- `transition` property in type-safe CSS (Plan 15)
- `keyframes` animation support
- Hover/focus/active state transitions
- Compile to pure CSS — zero JS

### Phase 2: View Transitions API (Week 3)
- `viewTransitionName` attribute
- Router integration for page transitions
- Cross-document transitions via CanopyKit

### Phase 3: Spring animations and scroll (Weeks 4-5)
- Spring physics runtime (~2KB)
- Scroll-driven animation primitives
- IntersectionObserver fallback

### Phase 4: Gestures (Week 6)
- Drag, swipe, pinch primitives
- Pointer event handling
- Velocity tracking for momentum

## Definition of Done

- [ ] CSS transitions compile to zero-JS output
- [ ] View Transitions API integrated with router
- [ ] Spring animations work with interruptible motion
- [ ] Scroll-driven reveals work cross-browser
- [ ] Staggered list animations
- [ ] Gesture handling (drag at minimum)
