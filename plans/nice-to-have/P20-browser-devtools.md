# Plan 20: Browser DevTools Extension

## Priority: LOW -- Tier 4
## Status: ~40% complete
## Effort: 3-4 weeks (revised down from 4-6 -- extension framework already exists)
## Depends on: Plan 01 (ESM), canopy-debugger tool exists

## What Already Exists

The browser debugger extension is **already built** at `~/projects/canopy/tools/canopy-debugger/`.

### Extension Framework (COMPLETE)
- **Chrome + Firefox** extension (WebExtensions API)
- **Tech stack**: React, Zustand (state management), Tailwind CSS
- **Time-travel debugging**: Step backward/forward through message history
- **State inspection**: Live view of application model and store state
- **Diff viewing**: See what changed between messages

### Runtime Debug Hook (COMPLETE)
- Compiler injects `window.__CANOPY_DEVTOOLS__` in dev mode (`--debug` flag)
- Content script <-> runtime bridge via `window.postMessage`
- Panel renders in Chrome/Firefox DevTools as a custom tab
- Production builds strip all debug infrastructure (zero overhead)

## What Remains

### Phase 1: Component Tree Visualization (Week 1)
- Visual tree of the application's page/component structure
- Each node shows: module name, which stores it reads, mount status, last render time
- Expand/collapse tree nodes, search by module name
- Highlight currently rendering components

### Phase 2: Message Timeline (Week 2)
- Chronological list of every message dispatched with timestamps
- Per-message detail: which model fields changed (diff), commands produced, time spent in `update`
- Filtering by message type, store, time range
- Export/import debug sessions (serialize timeline to JSON)

### Phase 3: Performance Profiling (Weeks 3-4)
- Render time per component (flame chart)
- Update time per message type
- Store update frequency and subscription count
- DOM mutation count per update cycle
- Memory allocation tracking
- Performance regression detection (compare against baseline)

## Architecture (Existing)

```
┌──────────────────────────────┐
│     Browser Extension        │
│  ┌────────┐  ┌────────────┐ │
│  │  Panel  │  │  Content   │ │
│  │  (React │<─>│  Script    │ │
│  │  Zustand│  │            │ │
│  │  TW CSS)│  └─────┬──────┘ │
│  └────────┘         │        │
└──────────────────────┼────────┘
                       │ window.postMessage
              ┌────────┴────────┐
              │  Canopy Runtime  │
              │  Debug Hook      │
              │  (__CANOPY_      │
              │   DEVTOOLS__)    │
              └─────────────────┘
```

## Dev Mode vs Prod Mode

- **Dev mode** (`canopy make`): Debug hook injected, full message logging, time-travel enabled
- **Prod mode** (`canopy make --optimize`): No debug hook, no logging, zero overhead
- The compiler strips all debug infrastructure in production builds

## Risks

- **Performance impact**: Logging every message and model snapshot adds overhead. Mitigate with lazy serialization (only serialize when the panel is open).
- **Large models**: Deep model trees may be slow to render in the panel. Mitigate with virtualized tree rendering and lazy expansion.
- **Cross-browser**: Must maintain compatibility across Chrome and Firefox WebExtensions API differences.
