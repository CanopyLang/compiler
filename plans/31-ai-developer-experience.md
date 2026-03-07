# Plan 31: AI Developer Experience

## Priority: MEDIUM — Tier 2
## Effort: 4-6 weeks
## Depends on: Stable compiler, LSP (already built)

## Problem

In 2026, 70%+ of developers use AI coding assistants daily. Languages that work well with AI tools get adopted faster. Canopy is uniquely positioned: strong types + explicit effects + pure functions mean AI can generate correct code more reliably than in any other frontend language.

But this advantage is latent — we need to activate it with tooling.

## Existing Assets

- **canopy-mcp**: MCP server already exists in the codebase
- **canopy-lsp**: Full LSP with hover, completions, diagnostics
- **Type system**: Every function has a precise type signature
- **Purity**: No hidden state mutations for AI to miss
- **FFI types**: `@canopy-type` annotations provide typed JS interop

## Solution: Four AI Integration Points

### 1. Enhanced MCP Server for AI Agents

Extend `canopy-mcp` so AI tools (Claude, GPT, Copilot) can:

```
canopy/compile       -- Compile a module, return typed errors
canopy/typeOf        -- Get the type of any expression
canopy/suggest       -- Get type-directed suggestions for a hole
canopy/explain       -- Explain a compile error in plain English
canopy/capabilities  -- List capabilities required by current code
canopy/docs          -- Get documentation for any module/function
```

This gives AI agents the compiler's knowledge directly, rather than guessing from source text.

### 2. Type-Directed Code Completion

The LSP already provides completions. Enhance it with:

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

**Decoder generation**: When the cursor is after `deriving (Decode)` (Plan 26b), show the generated decoder inline. Before abilities ship, offer a code action "Generate JSON decoder for this type."

### 3. AI-Assisted Migration Tool

```bash
canopy migrate --from react src/Component.tsx
canopy migrate --from elm src/Page.elm
```

Takes React/Elm source and produces Canopy source:
- Maps React hooks to TEA patterns
- Maps React.useState to Model fields
- Maps useEffect to Cmd/Sub
- Maps Elm kernel imports to FFI imports
- Preserves type information where available

This is powered by the compiler's type system — after initial conversion, run the type checker and use errors to guide refinement.

### 4. Contextual Error Explanations

Enhance error messages with optional AI-style explanations:

```bash
canopy build --explain
```

```
-- TYPE MISMATCH ────────────────── src/App.can

The 2nd argument to `div` has the wrong type:

    15| div [ class "main" ] model.items
                             ^^^^^^^^^^^

`model.items` is:

    List Item

But `div` expects its 2nd argument to be:

    List (Html Msg)

Explanation: You're passing raw data to a view function that expects
rendered HTML. You probably want to map each item through a view function:

    div [ class "main" ] (List.map viewItem model.items)
```

The "Explanation" section uses the type context to generate specific, actionable guidance. This can start as template-based (no LLM needed) and later integrate with AI for complex cases.

## Implementation Phases

### Phase 1: MCP Server Enhancement (Weeks 1-2)
- Extend canopy-mcp with compile/typeOf/suggest/explain endpoints
- Add capability listing endpoint
- Test with Claude Code and VS Code Copilot

### Phase 2: Typed Holes + Enhanced LSP (Weeks 3-4)
- Implement typed hole (`_`) support in the parser
- Type inference for holes during constraint solving
- LSP code actions for hole filling
- LSP code actions for JSON decoder generation

### Phase 3: Migration Tool (Weeks 5-6)
- React-to-Canopy basic conversion (component → module, hooks → TEA)
- Elm-to-Canopy conversion (module rename, kernel → FFI)
- Type-checker-guided refinement loop
- Documentation: "Migrating from React/Elm to Canopy"

## Why This Matters

React Compiler v1.0 (October 2025) proved that compiler intelligence is the future. But React Compiler works with JavaScript — it has limited type information. Canopy's compiler knows everything: types, effects, purity, capabilities.

When an AI assistant uses Canopy's MCP server, it gets:
- Exact types for every expression (not inferred from usage patterns)
- Exact effects for every function (not guessed from import statements)
- Exact capabilities required (not audited manually)

This makes AI-generated Canopy code dramatically more reliable than AI-generated React/Vue/Angular code.

## Definition of Done

- [ ] canopy-mcp serves compile/typeOf/suggest/explain endpoints
- [ ] AI agents can compile Canopy code and get structured type errors
- [ ] Typed holes show suggestions in LSP
- [ ] `canopy migrate --from elm` converts basic Elm modules
- [ ] Error messages include contextual explanations with `--explain`
