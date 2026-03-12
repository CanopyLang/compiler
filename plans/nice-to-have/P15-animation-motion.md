# Plan 15: Animation & Motion System

## Priority: MEDIUM — Tier 3
## Status: ~50% complete (core animation library and spring physics exist)
## Effort: 2-3 weeks (reduced from 4-6 — core libraries exist)
## Depends on: Plan 03 (packages — COMPLETE), CanopyKit router (for View Transitions)

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| `canopy/animation` | stdlib package (7 files) | COMPLETE — CSS keyframe animation library |
| `canopy/animation-motion` | stdlib package | COMPLETE — spring physics engine |
| CSS transitions | `canopy/animation` | COMPLETE — declarative CSS transition helpers |
| Keyframe animations | `canopy/animation` | COMPLETE — `@keyframes` generation |
| Spring physics | `canopy/animation-motion` | COMPLETE — spring-based animation with velocity/damping |
| Easing functions | `canopy/animation` | COMPLETE — standard easing curves |

The animation foundation is solid. `canopy/animation` (7 files) provides CSS keyframe animations, transitions, and easing functions. `canopy/animation-motion` adds spring physics with interruptible motion. Together these cover the most common animation use cases.

What does NOT exist: View Transitions API integration (requires a router), gesture handling, and scroll-driven animations.

## What Remains

### Phase 1: View Transitions API Integration (Week 1)

Requires CanopyKit router to be available. The View Transitions API animates between page navigations natively in the browser.

- `viewTransitionName : String -> Attribute msg` attribute for marking elements that should animate across page transitions
- Router integration: when navigating between routes, the router wraps the transition in `document.startViewTransition()`
- The compiler generates unique `view-transition-name` attributes and matching CSS for cross-page element transitions
- Fallback for browsers without View Transitions API support (immediate swap, no animation)

### Phase 2: Scroll-Driven Animations (Week 2)

CSS `scroll-timeline` and `animation-timeline` for scroll-linked effects:

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

- Compile to CSS `scroll-timeline` where browser-supported
- Fall back to `IntersectionObserver` for unsupported browsers
- Parallax effects via scroll position mapping
- Reveal-on-scroll patterns (fade in, slide up)

### Phase 3: Gesture Handling (Week 3)

Pointer event-based gesture recognition:

- **Drag**: horizontal/vertical/free axis with configurable constraints
- **Swipe**: velocity-based swipe detection with threshold
- **Pinch**: two-finger zoom gesture (mobile)
- Velocity tracking for momentum-based animations (flick to dismiss, throw to scroll)
- Integration with spring physics from `canopy/animation-motion` for natural-feeling gesture responses

```canopy
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

### Compiler Optimization

The compiler analyzes animation expressions and chooses the best strategy:

1. **Static transitions** (hover, focus) — pure CSS, zero JS (already handled by `canopy/animation`)
2. **Scroll-driven** — CSS `scroll-timeline` where supported, zero JS
3. **Spring/physics** — `requestAnimationFrame` JS via `canopy/animation-motion`
4. **View transitions** — View Transitions API (browser-native)
5. **Gesture-driven** — pointer events + `requestAnimationFrame`

## Dependencies

- `canopy/animation` (7 files) — provides CSS animation foundation
- `canopy/animation-motion` — provides spring physics engine
- CanopyKit router — required for View Transitions API integration (Phase 1)
- `canopy/css` — type-safe CSS properties used in animation value types

## Risks

- **View Transitions API browser support**: Safari 18.0+ and Chrome 111+ support it. Firefox support is recent. The fallback (immediate swap) is acceptable but means the feature degrades on older browsers.
- **Gesture complexity**: Multi-touch gestures on mobile are notoriously tricky. Start with single-pointer drag/swipe; add pinch/rotate as a follow-up.
- **Performance on low-end devices**: Spring physics animations run per-frame JavaScript. The existing `canopy/animation-motion` library handles this, but gesture + spring combinations need profiling on mobile devices.
