# Plan 07: Streaming SSR + Resumability

## Priority: HIGH — Tier 1
## Effort: 6-8 weeks
## Depends on: Plan 01 (ESM), Plan 03 (packages), Plan 05 (CanopyKit)

## Problem

SSR is table-stakes in 2026. Without it:
- SEO fails (blank HTML for crawlers)
- Core Web Vitals suffer (slow FCP/LCP)
- Enterprise teams won't adopt

But traditional SSR (render on server → hydrate on client) is expensive. React hydration re-executes all component code on the client. For large apps, this means seconds of JS execution before interactivity.

## Solution: Dual Compilation + Resumability

The compiler generates TWO outputs from the same source:

### 1. Server Output: HTML String Generation

The `view` function compiles to a string concatenation function for the server:

```canopy
-- Source
view model =
    div [ class "counter" ]
        [ text (String.fromInt model.count)
        , button [ onClick Increment ] [ text "+" ]
        ]
```

```javascript
// Server output
export function _renderToString(model) {
  return '<div class="counter">'
    + String(model.count)
    + '<button q:on:click="./App.js#_increment">+</button>'
    + '</div>';
}
```

Note: event handlers are serialized as **references**, not as code. The client loads the handler lazily on first interaction (Qwik-style).

### 2. Client Output: Resumable DOM Operations

Instead of hydrating (re-executing all code to rebuild state), the client **resumes**:

1. Server serializes the model into a `<script>` tag in the HTML
2. Client parses the serialized model
3. Client attaches event listeners to existing DOM nodes (no re-render)
4. On first state change, the reactive update system (Plan 04) takes over

```html
<!-- Server-rendered HTML -->
<div class="counter" q:id="0">
  42
  <button q:on:click="./App.js#_increment">+</button>
</div>
<script type="canopy/state">{"count":42}</script>
<script type="canopy/loader" src="canopy-loader.js"></script>
```

The loader (~1KB) sets up global event delegation. When the user clicks the button:
1. Loader intercepts the click
2. Loads `./App.js` (the compiled module)
3. Calls `_increment` with the current model
4. Reactive update system patches only the changed DOM nodes

### 3. Streaming

HTML is sent in chunks as data becomes available:

```canopy
page =
    Page.server
        { load = loadData
        , view = view
        }

-- loadData fetches from database (slow)
-- view renders the page

-- The shell (layout, nav, static content) streams immediately
-- The dynamic content (loaded data) streams when ready
-- A small inline script moves the streamed content into its placeholder
```

Implementation uses `Transfer-Encoding: chunked`:

```
<!-- Sent immediately -->
<html><body>
<nav>...</nav>
<main>
  <div id="placeholder-0">Loading...</div>

<!-- Sent when data resolves -->
<template id="resolved-0">
  <div class="post">Actual content here</div>
</template>
<script>
  document.getElementById('placeholder-0').replaceWith(
    document.getElementById('resolved-0').content
  );
</script>
</body></html>
```

## Compiler Changes

### Dual Codegen Mode

The code generation phase needs a target parameter:

```haskell
data Target = Client | Server

generate :: Target -> AST.Optimized.GlobalGraph -> ...
```

**Server mode:**
- `view` compiles to string concatenation (no DOM APIs)
- Signals/effects are stripped (overhead on server)
- `load` functions are included
- Event handlers serialized as references (module + symbol name)

**Client mode:**
- `view` compiles to reactive DOM operations (Plan 04) OR hydration code
- `load` functions excluded (server-only)
- Event handlers compiled normally
- Includes the resumption bootstrap

### Model Serialization

The compiler auto-generates JSON encoder/decoder for the page's Model type:

```haskell
-- For each page module with a Model type, generate:
encodeModel : Model -> Json.Value
decodeModel : Json.Decoder Model
```

This is derived from the type — no user code needed. The compiler already knows the structure of every type.

### Server/Client Boundary Enforcement

The type system (via capabilities) prevents mixing:

- Server `load` functions can use `ServerCapability` (database, filesystem)
- Client `view`/`update` functions can use `BrowserCapability` (DOM, localStorage)
- The compiler rejects server capabilities in client code and vice versa

## Performance Targets

| Metric | Traditional SSR | Resumable SSR (target) |
|--------|----------------|----------------------|
| Time to First Byte | 200-500ms | < 100ms (streaming) |
| Time to Interactive | TTFB + hydration (1-5s) | TTFB + 0ms (no hydration) |
| Client JS for static page | Full bundle | ~1KB loader only |
| Client JS for interactive page | Full bundle | Loaded on demand |

## Implementation Phases

### Phase 1: Basic SSR (Weeks 1-3)
- Server-side string rendering for `view` functions
- Model serialization/deserialization
- Basic `renderToString` in Node.js
- No streaming, no resumability yet — just traditional SSR + hydration

### Phase 2: Streaming (Weeks 4-5)
- `renderToStream` using Node.js ReadableStream
- Placeholder/resolution pattern for async data
- Chunked transfer encoding

### Phase 3: Resumability (Weeks 6-8)
- Event handler serialization (QRL-style references)
- Canopy loader script (~1KB)
- Lazy module loading on interaction
- State serialization into HTML
- Remove hydration entirely — resume from serialized state

## Risks

- **Model serialization**: Some types (functions, opaque types) can't be serialized. The compiler must detect these and either error or use a fallback.
- **Third-party JS**: If the page uses FFI that has client-side initialization, resumability may not work cleanly. Solution: allow `onResume` hooks for FFI modules.
- **SEO verification**: Test with Googlebot, Bing crawler, social media scrapers to ensure SSR output is correct.
