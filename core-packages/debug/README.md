# Canopy Debug Package

A comprehensive debugging solution for Canopy applications, featuring improved console logging and time-travel debugging.

## Debug.Console - Better Console Logging

Unlike the standard `Debug.log` which outputs `<internals>` or Elm-formatted strings, `Debug.Console` outputs **actual JSON objects** that you can inspect in the browser DevTools.

### The Problem with Standard Debug.log

```canopy
-- Standard Debug.log outputs:
-- user: { name = "Alice", age = 30 }  (as a string, not inspectable)

-- Functions show nothing useful:
-- myFunc: <function>  (no arity info)
```

### The Solution: Debug.Console

```canopy
import Debug.Console

-- Outputs actual JSON objects you can expand in DevTools
Debug.Console.log "user" user
-- Console: user: {name: "Alice", age: 30}  (expandable object!)

-- Shows function arity (great for debugging partial application)
Debug.Console.log "handler" myPartialFunction
-- Console: handler: <function:2 args remaining>

-- Additional methods
Debug.Console.warn "deprecation" value    -- Yellow warning
Debug.Console.error "validation" errors   -- Red error
Debug.Console.table "users" userList      -- Table view
Debug.Console.inspect "model" model       -- Deep inspection with types
Debug.Console.time "compile"              -- Start timer
Debug.Console.timeEnd "compile"           -- End timer (shows elapsed)
```

### Usage

The Debug.Console module is automatically bundled with your application - no extra scripts needed:

```canopy
import Debug.Console

main =
    let
        user = { name = "Alice", age = 30 }
        _ = Debug.Console.log "user" user
    in
    view user
```

## Time-Travel Debugger

### Features

- **Message Recording**: Automatically captures all messages sent to your `update` function
- **State Snapshots**: Takes snapshots of application state at each step
- **Time Travel**: Navigate forward and backward through application history
- **State Inspection**: Inspect state at any point in time with tree view and diff visualization
- **Message Filtering**: Filter messages by type or content
- **Session Export/Import**: Save and share debugging sessions

## Installation

### Debug Runtime

Add to your `canopy.json`:

```json
{
  "dependencies": {
    "canopy/debug": "1.0.0"
  }
}
```

### Browser Extension

1. Build the extension:
   ```bash
   cd tools/canopy-debugger
   npm install
   npm run build:chrome
   ```

2. Load in Chrome:
   - Open `chrome://extensions`
   - Enable "Developer mode"
   - Click "Load unpacked"
   - Select the `dist` folder

### VS Code Integration

The debugger is built into the Canopy VS Code extension. Access it via:
- Command Palette: "Canopy: Open Time-Travel Debugger"
- Or use the keyboard shortcut

## Usage

### Basic Setup

Wrap your application with the debugger:

```elm
import Debug

main =
    Debug.wrap
        { init = init
        , update = update
        , view = view
        }
```

For applications with commands:

```elm
main =
    Debug.wrapWithFlags
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
```

### Debug Server

Start the debug server to connect browser extension and VS Code:

```bash
npx canopy-debug-server
# or
node core-packages/debug/debug-server.js
```

Options:
- `--port, -p`: Port number (default: 8765)
- `--host, -h`: Host address (default: localhost)

### Keyboard Shortcuts

In the debugger UI:
- `Left Arrow`: Step backward
- `Right Arrow`: Step forward
- `Space`: Toggle pause
- `Escape`: Clear selection
- `Ctrl+E`: Export session
- `Ctrl+I`: Import session

## API Reference

### Debug Module

```elm
-- Initialize debugger with configuration
init : Config -> model -> Debugger model msg

-- Wrap a sandbox program
wrap : { init, update, view } -> Program () (DebugModel model msg) (DebugMsg msg)

-- Wrap a program with flags
wrapWithFlags : { init, update, view, subscriptions } -> Program flags (DebugModel model msg) (DebugMsg msg)

-- Record a state change
record : msg -> model -> Debugger model msg -> Debugger model msg

-- Get history
getHistory : Debugger model msg -> History model msg

-- Time travel
stepForward : Debugger model msg -> Debugger model msg
stepBackward : Debugger model msg -> Debugger model msg
jumpTo : Int -> Debugger model msg -> Debugger model msg

-- Session management
exportSession : Debugger model msg -> String
importSession : String -> Debugger model msg -> Result String (Debugger model msg)
```

### Configuration

```elm
type alias Config =
    { maxHistory : Int           -- Maximum history entries (default: 1000)
    , enableWebSocket : Bool     -- Enable external debugger connection
    , websocketUrl : String      -- WebSocket URL (default: ws://localhost:8765)
    , pauseOnStart : Bool        -- Pause on application start
    , filterMessages : List String -- Message types to filter out
    }
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Canopy Application                    │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   │
│  │   update    │ → │   Debug     │ → │   state     │   │
│  │  function   │   │   Runtime   │   │  snapshot   │   │
│  └─────────────┘   └──────┬──────┘   └─────────────┘   │
└──────────────────────────┼──────────────────────────────┘
                           │ WebSocket
                           ▼
              ┌─────────────────────────┐
              │      Debug Server       │
              │     (ws://localhost)    │
              └────────────┬────────────┘
                    ┌──────┴──────┐
                    │             │
        ┌───────────▼──┐   ┌──────▼───────┐
        │   Browser    │   │   VS Code    │
        │  Extension   │   │    Panel     │
        └──────────────┘   └──────────────┘
```

## Troubleshooting

### WebSocket Connection Issues

1. Ensure the debug server is running
2. Check firewall settings for port 8765
3. Verify the WebSocket URL in configuration

### Performance Considerations

- Reduce `maxHistory` for memory-constrained environments
- Use `filterMessages` to exclude high-frequency messages (e.g., animation ticks)
- The debugger adds minimal overhead when not actively inspecting

### State Not Updating

- Ensure your application is wrapped with `Debug.wrap` or `Debug.wrapWithFlags`
- Check browser console for connection errors
- Verify the debug runtime is properly imported

## License

BSD-3-Clause
