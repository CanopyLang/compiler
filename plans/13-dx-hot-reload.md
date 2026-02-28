# Plan 13: Hot Reload / Watch Mode Enhancement

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Medium — real-time compilation requires robust error recovery

## Problem

`canopy watch` exists but needs enhancement for developer experience:
- No browser auto-refresh integration
- No incremental recompilation on watch
- No WebSocket-based live reload

## Implementation Plan

### Step 1: Add WebSocket live reload server

**File**: `packages/canopy-terminal/src/Watch/LiveReload.hs` (NEW)

Embed a lightweight WebSocket server that notifies connected browsers on recompilation:

```haskell
data LiveReloadServer = LiveReloadServer
  { _lrsPort :: !Int
  , _lrsClients :: !(TVar [WebSocket.Connection])
  }

startServer :: Int -> IO LiveReloadServer
notifyClients :: LiveReloadServer -> IO ()
```

### Step 2: Inject live reload script

When compiling in watch mode with `--live-reload`, inject a small JavaScript snippet into generated HTML that connects to the WebSocket server:

```javascript
new WebSocket('ws://localhost:8234').onmessage = () => location.reload();
```

### Step 3: Incremental watch compilation

Integrate with Plan 09 (incremental type checking) to only recompile changed modules and their dependents:

```haskell
watchLoop :: WatchState -> FSEvent -> IO WatchState
watchLoop state event = do
  let changedModules = affectedModules state event
  result <- recompileSubset state changedModules
  notifyBrowser result
  pure (updateState state result)
```

### Step 4: Error overlay

When compilation fails in watch mode, inject an error overlay into the browser instead of a blank page:

```javascript
// Show compilation error as a styled overlay
document.body.innerHTML = '<pre style="...">' + errorMessage + '</pre>';
```

### Step 5: CLI flags

- `--live-reload` — enable browser refresh (default: off)
- `--live-reload-port <port>` — WebSocket port (default: 8234)
- `--no-browser` — don't open browser on start

### Step 6: Tests

- Test WebSocket server starts and accepts connections
- Test notification on file change
- Test error overlay generation
- Test incremental recompilation in watch mode

## Dependencies
- Plan 09 (incremental type checking) for efficient recompilation
