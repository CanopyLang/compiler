# Plan 10: Browser DevTools Extension

## Priority: HIGH — Tier 2
## Effort: 4-6 weeks
## Depends on: Plan 01 (ESM) — Plan 03 COMPLETE, canopy-debugger tool exists

## Problem

React DevTools is a daily-driver tool for React developers. It provides:
- Component tree visualization
- Props/state inspection
- Performance profiling
- Time-travel debugging (via Redux DevTools)

Canopy developers currently have no equivalent. Elm had elm-reactor's debugger, but it was removed and never replaced.

## Solution: Canopy DevTools

A Chrome/Firefox browser extension that provides deep insight into Canopy applications.

### Features

#### 1. Component Tree
Visual tree of the application's page/component structure:

```
App
├── Layout.Default
│   ├── Navbar (Store: User)
│   ├── Routes.Blog.Page
│   │   ├── PostList (Store: Posts)
│   │   └── Sidebar
│   └── Footer
```

Each node shows:
- Module name
- Which stores it reads
- Whether it's currently mounted
- Last render time

#### 2. Model Inspector
Live view of the application's model and store state:

```
Model: App
├── page: BlogList
├── userStore: Store User
│   ├── name: "Alice"
│   ├── email: "alice@example.com"
│   └── role: Admin
└── cartStore: Store Cart
    ├── items: List (3 items)
    │   ├── [0]: { id: "abc", qty: 2, price: 29.99 }
    │   ├── [1]: { id: "def", qty: 1, price: 15.00 }
    │   └── [2]: { id: "ghi", qty: 1, price: 42.50 }
    └── total: 117.48
```

Values update in real-time. Click to expand/collapse. Search by path.

#### 3. Message Timeline
Chronological list of every message dispatched:

```
12:03:45.123  UserClickedLogin         → Model updated (2 fields)
12:03:45.456  LoginResponse (Ok user)  → Model updated (3 fields), Store: User updated
12:03:46.789  NavigateTo Dashboard     → Model updated (1 field)
12:03:47.012  LoadDashboardData        → Cmd: Http.get "/api/dashboard"
```

Each message shows:
- Timestamp
- Message constructor + payload
- Which model fields changed (diff)
- Which stores were updated
- Commands produced
- Time spent in `update`

#### 4. Time-Travel Debugging
Step backward/forward through the message history:

- Click any message in the timeline to restore the model to that point
- The UI re-renders with the historical state
- "Play forward" to replay messages from a historical point
- Export/import debug sessions (serialize timeline to JSON)

#### 5. Performance Profiler
- Render time per component
- Update time per message type
- Store update frequency
- DOM mutation count per update cycle
- Flame chart of the update→render pipeline

### Architecture

```
┌──────────────────────────────┐
│     Browser Extension        │
│  ┌────────┐  ┌────────────┐ │
│  │  Panel  │  │  Content   │ │
│  │  (UI)   │←→│  Script    │ │
│  └────────┘  └─────┬──────┘ │
└──────────────────────┼───────┘
                       │ window.postMessage
              ┌────────┴────────┐
              │  Canopy Runtime  │
              │  Debug Hook      │
              └─────────────────┘
```

#### Runtime Debug Hook

The compiler (in dev mode) injects a debug hook into the generated code:

```javascript
// Injected when --debug flag is set
window.__CANOPY_DEVTOOLS__ = {
  getModel: () => currentModel,
  getStores: () => storeMap,
  getMessageLog: () => messageLog,
  onMessage: (callback) => messageListeners.push(callback),
  timeTravel: (index) => restoreState(messageLog[index].modelAfter),
  getComponentTree: () => componentTree,
};
```

The content script connects to this hook and relays data to the DevTools panel.

#### Panel UI

Built with web technologies (HTML/CSS/JS or even Canopy itself). Renders in Chrome DevTools as a custom panel tab.

### Implementation Phases

### Phase 1: Model Inspector (Weeks 1-2)
- Runtime debug hook injection (compiler flag)
- Content script ↔ runtime bridge
- Panel with model tree viewer
- Real-time model updates

### Phase 2: Message Timeline (Weeks 3-4)
- Message logging in the runtime
- Timeline UI with filtering
- Model diff per message
- Basic time-travel (click to restore)

### Phase 3: Component Tree + Profiling (Weeks 5-6)
- Component tree tracking (requires reactive compiler or VDOM instrumentation)
- Render time measurement
- Performance flame chart
- Store subscription visualization

## Dev Mode vs Prod Mode

- **Dev mode** (`canopy make`): Debug hook injected, full message logging, time-travel enabled
- **Prod mode** (`canopy make --optimize`): No debug hook, no logging, zero overhead
- The compiler strips all debug infrastructure in production builds

## Risks

- **Performance impact**: Logging every message and model snapshot adds overhead. Mitigate with lazy serialization (only serialize when the panel is open).
- **Large models**: Deep model trees may be slow to render in the panel. Mitigate with virtualized tree rendering and lazy expansion.
- **Cross-browser**: Must work in Chrome and Firefox at minimum. Use the WebExtensions API for compatibility.
