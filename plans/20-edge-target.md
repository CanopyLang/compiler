# Plan 20: Edge Computing Target

## Priority: LOW — Tier 4
## Effort: 3-4 weeks
## Depends on: Plan 01 (ESM), Plan 07 (SSR), Plan 05 (CanopyKit)

## Problem

Edge runtimes (Cloudflare Workers, Deno Deploy, Vercel Edge) run JavaScript at CDN nodes worldwide, reducing latency to < 50ms for most users. But they have strict constraints:

| Platform | Bundle Size Limit | CPU Time | Memory |
|----------|------------------|----------|--------|
| Cloudflare Workers (free) | 1 MB | 50ms | 128 MB |
| Cloudflare Workers (paid) | 10 MB | 30s | 128 MB |
| Vercel Edge Functions | 4.5 MB | 25ms CPU | Limited |

A pure functional language is a perfect fit: request → response is just a pure function. But the compiler must enforce edge constraints.

## Solution

### Edge-Aware Compilation

```bash
canopy build --target edge
```

This flag:
1. Enforces WinterTC API surface (no Node.js APIs)
2. Warns on bundle size exceeding platform limits
3. Strips dev-only code and debug infrastructure
4. Optimizes for minimal startup time

### Capability System Integration

Edge runtimes expose a limited API set. The capability system (Plan 13) enforces this:

```canopy
-- canopy.json for an edge project:
{
  "target": "edge",
  "capabilities": {
    "allow": ["fetch", "crypto", "kv-storage", "cache"],
    "deny": ["filesystem", "child-process", "dom"]
  }
}
```

Using a denied capability is a compile error:

```
── UNAVAILABLE ON EDGE ──────────────── src/Handler.can

This function uses File.read, which requires the "filesystem" capability.
This capability is not available on edge runtimes.

    12│  contents <- File.read "config.json"

Consider using KV storage or environment variables instead.
```

### Edge Request Handler

```canopy
module Handler exposing (handler)

handler : Request -> Task Never Response
handler request =
    case Request.path request of
        "/api/users" ->
            KV.get "users"
                |> Task.map Response.json

        "/api/health" ->
            Task.succeed (Response.text "ok")

        _ ->
            Task.succeed (Response.notFound "Not found")
```

### CanopyKit Edge Adapter

```canopy
-- canopykit.config.can
config =
    CanopyKit.config
        { adapter = CanopyKit.Adapter.cloudflareWorkers
        -- OR: CanopyKit.Adapter.vercelEdge
        -- OR: CanopyKit.Adapter.denoDeply
        }
```

The adapter generates the platform-specific entry point:

```javascript
// Generated: _worker.js (Cloudflare Workers format)
export default {
  async fetch(request, env, ctx) {
    return await CanopyHandler.handler(request);
  }
};
```

## Implementation

### Phase 1: WinterTC API types (Week 1)
- Define Canopy types for: Request, Response, Headers, URL, fetch, crypto.subtle, TextEncoder/Decoder, ReadableStream/WritableStream, AbortController
- These are the standard Web APIs available on all edge runtimes

### Phase 2: Edge compilation mode (Week 2)
- `--target edge` flag
- Bundle size checking and warnings
- Strip unused code aggressively (whole-program DCE)
- No DOM APIs in scope

### Phase 3: Platform adapters (Weeks 3-4)
- Cloudflare Workers adapter (entry point format, KV bindings, Durable Objects)
- Vercel Edge adapter (entry point format, environment variables)
- Deno Deploy adapter (entry point format, Deno.serve)
- Each adapter generates the platform-specific boilerplate

## Definition of Done

- [ ] `canopy build --target edge` produces a working Cloudflare Worker
- [ ] Bundle size warnings at 500KB / 1MB / 5MB thresholds
- [ ] WinterTC APIs available as typed Canopy modules
- [ ] Capability system prevents DOM/Node.js API usage
- [ ] At least one CanopyKit adapter (Cloudflare Workers)
