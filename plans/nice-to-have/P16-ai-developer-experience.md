# Plan 16: AI Developer Experience

## Priority: MEDIUM — Tier 2
## Status: ~60% complete (MCP server, LSP, playground all exist)
## Effort: 2-3 weeks (reduced from 3-4 — substantial infrastructure exists)
## Depends on: Stable compiler, LSP (COMPLETE)

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| MCP server | `canopy-mcp` | COMPLETE — 12 tools, 3 prompts |
| TypeScript LSP | `language-server/` | COMPLETE — 15+ providers |
| Playground | `tools/playground/` | COMPLETE — React/Vite app |
| Debugger | `tools/canopy-debugger/` | COMPLETE — Vite-based |
| VSCode extension | repo | COMPLETE |
| Tree-sitter grammar | repo | COMPLETE |

### MCP Server (12 Tools, 3 Prompts)

Tools:
- `canopy_build` — compile with output format selection (iife/esm/commonjs)
- `canopy_check` — type check without generating output
- `canopy_get_type` — get type of expression at file:line:column
- `canopy_find_definition` — go-to-definition for symbols
- `canopy_get_docs` — documentation for modules/functions
- `canopy_list_modules` — list all modules in the project
- `canopy_format` — format source code
- `canopy_lint` — lint source code
- `canopy_get_completions` — get completions at a position
- `canopy_get_dependencies` — get dependency graph
- `canopy_get_errors` — get all errors in the project
- `canopy_get_outline` — get module outline (types, functions, exports)

Prompts:
- `canopy_new_module` — scaffold a new module
- `canopy_tea_component` — scaffold a TEA component
- `canopy_fix_error` — diagnose and fix a compile error

### TypeScript LSP (15+ Providers)

- 25+ code action providers (add missing case branches, extract function, import, etc.)
- Diagnostics from compiler, elm-review, and built-in analysis
- Completion, hover, definition, references, rename, folding, symbols
- Code lens, linked editing ranges, selection ranges

## What Remains

### Phase 1: MCP Server Enhancement (Week 1)

Add 3-4 targeted tools to fill gaps in AI-assisted development:

- `canopy_suggest` — type-directed suggestions for a hole position (given a file, line, column, return all values in scope matching the expected type)
- `canopy_explain` — explain a compile error in plain English with fix suggestions (wraps the compiler's error output with additional context)
- `canopy_capabilities` — list ability requirements for current code (which abilities are used, which implementations are needed)

The existing 12 tools handle the core workflow. These additions close the gap for AI agents that need to reason about types and errors without parsing compiler output.

### Phase 2: Typed Holes in Compiler (Weeks 2-3)

When the developer writes `_` in an expression position, the compiler:

1. Infers the expected type at that position during constraint solving
2. Collects all values in scope that match the expected type
3. Ranks suggestions by relevance (local bindings first, then imports, then qualified)
4. Reports the hole type and suggestions in the error message

LSP integration:
- Hole types shown in hover information
- Code actions to fill holes with suggested values
- Quick fix suggestions ranked by type match quality

This is compiler work (new expression variant in the parser, constraint generation for holes, suggestion collection in the type checker) plus LSP provider updates.

### Phase 3: AI Training Corpus (Future)

- Curated set of Canopy code examples optimized for AI training
- Migration tool: `canopy migrate --from react src/Component.tsx`
- Depends on abilities (P06 — COMPLETE) and TypeScript interop being further along

## Dependencies

- MCP server (12 tools) — enhancement target
- LSP (15+ providers) — typed holes surface through LSP
- Compiler parser — `_` as expression variant
- Compiler type checker — hole inference and suggestion collection

## Risks

- **Typed hole performance**: Collecting all values in scope matching a type can be expensive in large projects. Limit search depth and cache type-compatible values per module.
- **Suggestion quality**: Ranking suggestions by type match alone may surface irrelevant values. Use heuristics: prefer local bindings, prefer shorter paths, prefer values whose names relate to the hole's context.
- **MCP protocol evolution**: The MCP specification is still evolving. The existing server works with current clients (Claude, Cursor) but may need updates as the protocol matures.
