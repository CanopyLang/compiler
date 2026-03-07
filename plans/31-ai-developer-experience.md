# Plan 31: AI Developer Experience

## Priority: MEDIUM — Tier 2
## Effort: 3-4 weeks (reduced — MCP server already exists with 5 tools)
## Depends on: Stable compiler, LSP (already built)

> **Status Update (2026-03-07 audit):** The MCP server (`canopy-mcp`) is **already built** with
> 5 working tools:
>
> - `canopy_build` — compile with output format selection (iife/esm/commonjs)
> - `canopy_check` — type check without generating output
> - `canopy_get_type` — get type of expression at file:line:column
> - `canopy_find_definition` — go-to-definition for symbols
> - `canopy_get_docs` — documentation for modules/functions
>
> Additionally, a **playground** exists at `compiler/tools/playground/` — a full React/TypeScript
> app with Vite, CodeMirror-style editor, preview panel, error display, example picker,
> sharing, and keyboard shortcuts.
>
> The LSP (`language-server/`) is a comprehensive TypeScript implementation with:
> - 25+ code action providers (add missing case branches, extract function, import, etc.)
> - Diagnostics from compiler, elm-review, and built-in analysis
> - Completion, hover, definition, references, rename, folding, symbols
> - Code lens, linked editing ranges, selection ranges

## Problem

In 2026, 70%+ of developers use AI coding assistants daily. Languages that work well with AI tools get adopted faster. Canopy is uniquely positioned: strong types + explicit effects + pure functions mean AI can generate correct code more reliably than in any other frontend language.

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| MCP server | `compiler/packages/canopy-mcp/` | Built — 5 tools |
| LSP | `language-server/` | Built — full-featured TypeScript implementation |
| Playground | `compiler/tools/playground/` | Built — React/Vite app |
| Debugger | `compiler/tools/canopy-debugger/` | Built — Vite-based |
| Tree-sitter grammar | (in LSP) | Built |
| VSCode extension | (in repo) | Built |

## Remaining Work

### Phase 1: MCP Server Enhancement (Weeks 1-2)

Extend `canopy-mcp` with additional tools:

```
canopy_suggest       -- Type-directed suggestions for a hole position
canopy_explain       -- Explain a compile error in plain English
canopy_capabilities  -- List capabilities required by current code
canopy_completions   -- Get completions at a position (expose LSP completions via MCP)
```

The existing `canopy_build`, `canopy_check`, `canopy_get_type`, `canopy_find_definition`, and `canopy_get_docs` tools handle the core use cases. The additions above fill the gaps for AI-assisted development.

### Phase 2: Typed Holes + Enhanced LSP (Weeks 3-4)

**Typed holes**: When the developer writes `_` in an expression position, the compiler infers the expected type and the LSP suggests all values in scope that match:

```canopy
update msg model =
    case msg of
        FetchedUsers result ->
            ( { model | users = _ }, Cmd.none )
            --                   ^ Expected: List User
            --                     Suggestions:
            --                       Result.withDefault [] result
            --                       model.users
            --                       []
```

Implementation:
- Add `_` (typed hole) support in the parser
- Type inference for holes during constraint solving
- LSP code actions for hole filling
- LSP code actions for JSON decoder generation (pre-Plan 26b)

### Phase 3: AI-Assisted Migration Tool (Future)

```bash
canopy migrate --from react src/Component.tsx
canopy migrate --from elm src/Page.elm
```

This depends on Plan 26b (abilities) and Plan 12 (TS interop) being further along. Deferred.

## Why This Matters

When an AI assistant uses Canopy's MCP server, it gets:
- Exact types for every expression (not inferred from usage patterns)
- Exact capabilities required (not audited manually)
- Compilation results with structured errors

This makes AI-generated Canopy code dramatically more reliable than AI-generated React/Vue/Angular code.

## Definition of Done

- [x] canopy-mcp serves build/check/getType/findDefinition/getDocs tools
- [ ] canopy-mcp serves suggest/explain/capabilities tools
- [ ] AI agents can compile Canopy code and get structured type errors
- [ ] Typed holes show suggestions in LSP
- [ ] Error messages include contextual explanations with `--explain`
