# Plan 22: Edge Computing Target

## Priority: LOW -- Tier 4
## Status: ~10% complete
## Effort: 3-4 weeks
## Depends on: Plan 01 (ESM), Plan 07 (SSR), Plan 05 (CanopyKit)

## What Already Exists

### Capability System (Plan 01 -- COMPLETE)
- Capability-based security model can enforce API restrictions per target
- `capabilities` field in `canopy.json` for allow/deny lists
- Compile-time errors when denied capabilities are used

### Related Infrastructure
- ESM code generation (Plan 01) provides the module format edge runtimes expect
- CanopyKit with SSR support (Plan 07) provides the server-side rendering pipeline
- 72 stdlib packages covering web APIs (many applicable to edge: fetch, crypto, streams)

## What Remains

### Phase 1: WinterTC API Types (Week 1)
- Define Canopy types for edge-standard APIs: Request, Response, Headers, URL
- Bindings for: `fetch`, `crypto.subtle`, `TextEncoder`/`TextDecoder`, `ReadableStream`/`WritableStream`, `AbortController`
- These are the standard Web APIs available on all edge runtimes (WinterTC specification)
- Capability: `temporal` for graceful fallback on older platforms

### Phase 2: Edge Compilation Mode (Week 2)
- `canopy build --target edge` flag
- Enforce WinterTC API surface (no Node.js APIs, no DOM APIs)
- Bundle size checking and warnings at 500KB / 1MB / 5MB thresholds
- Strip dev-only code and debug infrastructure
- Whole-program dead code elimination optimized for minimal startup time

### Phase 3: Platform Adapters (Weeks 3-4)
- **Cloudflare Workers**: Entry point format, KV bindings, Durable Objects
- **Vercel Edge Functions**: Entry point format, environment variables
- **Deno Deploy**: Entry point format, `Deno.serve`
- Each adapter generates platform-specific boilerplate from CanopyKit config:
  ```canopy
  config =
      CanopyKit.config
          { adapter = CanopyKit.Adapter.cloudflareWorkers }
  ```

## Capability System Integration

Edge runtimes expose a limited API set. The existing capability system enforces this at compile time:

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

Using a denied capability produces a compile error:

```
-- UNAVAILABLE ON EDGE -------------------- src/Handler.can

This function uses File.read, which requires the "filesystem" capability.
This capability is not available on edge runtimes.

    12|  contents <- File.read "config.json"

Consider using KV storage or environment variables instead.
```

## Edge Runtime Constraints

| Platform | Bundle Size Limit | CPU Time | Memory |
|----------|------------------|----------|--------|
| Cloudflare Workers (free) | 1 MB | 50ms | 128 MB |
| Cloudflare Workers (paid) | 10 MB | 30s | 128 MB |
| Vercel Edge Functions | 4.5 MB | 25ms CPU | Limited |

A pure functional language is a natural fit: request -> response is a pure function.

## Definition of Done

- [ ] `canopy build --target edge` produces a working Cloudflare Worker
- [ ] Bundle size warnings at 500KB / 1MB / 5MB thresholds
- [ ] WinterTC APIs available as typed Canopy modules
- [ ] Capability system prevents DOM/Node.js API usage in edge target
- [ ] At least one CanopyKit adapter (Cloudflare Workers)

## Risks

- **Platform fragmentation**: Edge runtimes differ in subtle API behaviors despite WinterTC standardization.
- **Cold start**: Must optimize for minimal startup time. Canopy's small output size is an advantage here.
- **Testing**: No local edge runtime emulator covers all platform quirks. Must test against real platforms.
