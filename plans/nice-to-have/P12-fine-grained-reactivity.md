# Plan 12: Fine-Grained Reactivity Compiler

## Priority: LOW — Tier 3
## Status: 0% complete (design only)
## Effort: 6-8 weeks
## Depends on: Plan 01 (ESM output), stable compiler, CanopyKit shipped first

## What Already Exists

| Component | Location | Status |
|-----------|----------|--------|
| `canopy/virtual-dom` | stdlib package | COMPLETE — VDOM diffing and patching |
| VDOM code generation | `Generate/JavaScript.hs` | COMPLETE — generates VDOM-based JS |
| Lighthouse score | Production apps | ~90 with current VDOM approach |

The current VDOM approach (inherited from Elm) is functional and performant. SolidJS scores ~98 and Svelte 5 scores ~96 on Lighthouse. The marginal improvement matters for benchmarks but not for adoption.

**Ship CanopyKit first.** Real users and real benchmarks should drive the decision to invest 6-8 weeks in a new rendering pipeline. This plan is ready to execute when the time comes.

## What Remains

The entire fine-grained reactivity system is new compiler work. Nothing from the existing VDOM pipeline is reused — the reactive compiler is a parallel code generation path.

### Phase 1: Template Analysis (Weeks 1-2)

New compiler pass that classifies every node in a `view` function:

- **Static nodes**: HTML structure that never changes (emit as template string, clone with `cloneNode(true)`)
- **Dynamic text**: Text depending on model fields (emit targeted `textContent` update)
- **Dynamic attributes**: Attributes depending on model fields (emit targeted `setAttribute` update)
- **Structural dynamics**: Conditionals (`if`), lists (`List.map`) (emit block-level insert/remove)

This analysis is possible because Canopy is pure — there are no hidden state reads.

### Phase 2: Dependency Tracking (Weeks 3-4)

For each dynamic expression, trace which model fields it reads:

- `text (String.fromInt model.count)` depends on `model.count` — update `textContent` when `model.count` changes
- `classList [("active", model.isActive)]` depends on `model.isActive` — toggle class when it changes

New IR between `AST.Optimized` and `Generate.JavaScript`:

```haskell
data ReactiveNode
  = StaticTemplate Builder
  | DynamicText [ModelPath]
  | DynamicAttr Attr [ModelPath]
  | ConditionalBlock [ModelPath] ReactiveNode ReactiveNode
  | ListBlock [ModelPath] ReactiveNode
  | ComponentMount ModuleName
```

### Phase 3: Reactive Code Generation (Weeks 5-6)

New module `Generate/JavaScript/Reactive.hs` that emits:

- **Mount function** (runs once): creates DOM from template strings, attaches event listeners, returns handles to dynamic nodes
- **Update function** (runs on state change): checks each model field for changes, updates only affected DOM nodes

### Phase 4: List Reconciliation (Week 7)

Keyed list reconciler for `List.map` in views. Diffs a flat list of keys (not a deep tree), creates/removes/moves DOM nodes, updates each item's dynamic nodes individually.

### Phase 5: Conditional Compilation (Week 8)

Pre-compiles both branches of `if` expressions as templates. Swaps them in/out based on the condition. Each branch has its own mount/update functions.

### Performance Targets

| Metric | Current (VDOM) | Target (Reactive) |
|--------|---------------|-------------------|
| Create 1K rows | ~30 ops/sec | >40 ops/sec |
| Update 1K rows | ~25 ops/sec | >35 ops/sec |
| Bundle size (hello world, gzip) | ~19 KB | < 2 KB |
| Startup time | ~50ms | < 30ms |

## Dependencies

- Plan 01 (ESM output) — reactive codegen targets ESM
- `canopy/virtual-dom` — VDOM path remains as fallback for patterns the reactive compiler cannot analyze
- `--reactive` flag enables new codegen (default once stable)

## Risks

- **Complex view functions**: Higher-order composition in `view` functions makes static analysis difficult. Solution: fall back to VDOM for those subtrees.
- **Third-party Html libraries**: Code constructing `Html` outside the view function may not be analyzable. Solution: treat unknown `Html` values as fully dynamic.
- **Maintenance cost**: Two code generation backends doubles complexity. Must ensure both produce correct, equivalent results. Extensive golden test coverage required.
