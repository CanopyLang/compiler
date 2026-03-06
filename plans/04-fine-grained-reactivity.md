# Plan 04: Fine-Grained Reactivity Compiler

## Priority: HIGH — Tier 1
## Effort: 6-8 weeks
## Depends on: Plan 01 (ESM output), Plan 03 (packages)

## Problem

Canopy currently uses a virtual DOM (inherited from Elm). The VDOM approach:

1. Reruns the entire `view` function on every state change, producing a full tree
2. Diffs the new tree against the old tree
3. Patches the real DOM with the differences

This is wasteful. SolidJS and Svelte 5 prove that a compiler can do better:

- **SolidJS**: Calls each component function once, then maps signal changes directly to specific DOM nodes. No diffing. Benchmarks: 42.8 ops/sec create 1K rows vs React's 28.4.
- **Svelte 5**: Compiles runes into `$.template_effect()` callbacks that update individual DOM nodes. ~55% smaller bundles than Svelte 4.

A pure functional language compiler has **more information** than either — we know every data dependency statically.

## The Approach

We do NOT change the programming model. Developers still write TEA (Model, update, view). The compiler analyzes the `view` function and compiles it to fine-grained DOM operations.

### Phase 1: Template Analysis

The compiler analyzes `view` function bodies to classify each node:

```canopy
view model =
    div []
        [ h1 [] [ text "Counter" ]            -- STATIC: never changes
        , p [] [ text (String.fromInt model.count) ]  -- DYNAMIC: depends on model.count
        , button [ onClick Increment ] [ text "+" ]   -- STATIC content, STATIC handler
        ]
```

Classification:
- **Static nodes**: HTML structure that never changes → emit as template string, clone with `cloneNode(true)`
- **Dynamic text**: Text that depends on model fields → emit as targeted `textContent` update
- **Dynamic attributes**: Attributes that depend on model → emit as targeted `setAttribute` update
- **Structural dynamics**: Conditionals (`if`), lists (`List.map`) → emit as block-level insert/remove

### Phase 2: Dependency Tracking

For each dynamic expression, the compiler traces which model fields it reads:

```
text (String.fromInt model.count)
  → depends on: model.count
  → update: set textContent of this node when model.count changes

classList [ ("active", model.isActive) ]
  → depends on: model.isActive
  → update: toggle "active" class when model.isActive changes
```

This is possible because Canopy is pure — there are no hidden state reads.

### Phase 3: Code Generation

Instead of generating a `view` function that returns a VDOM tree, generate:

**Initial render function** (runs once):
```javascript
export function _mount(root) {
  const _tmpl = _template('<div><h1>Counter</h1><p></p><button>+</button></div>');
  const _el = _tmpl.cloneNode(true);
  const _p = _el.childNodes[1];
  const _btn = _el.childNodes[2];
  _btn.addEventListener('click', () => _dispatch(Increment));
  root.appendChild(_el);
  return { _p };  // return handles to dynamic nodes
}
```

**Update function** (runs on state change, targets only affected nodes):
```javascript
export function _update(handles, oldModel, newModel) {
  if (oldModel.count !== newModel.count) {
    handles._p.textContent = String(newModel.count);
  }
}
```

### Phase 4: List Reconciliation

For `List.map` in views, generate a keyed list reconciler:

```canopy
view model =
    ul [] (List.map viewItem model.items)
```

Compiles to a reconciler that:
1. Diffs the list by key (if `Html.Keyed` is used) or by index
2. Creates/removes/moves DOM nodes as needed
3. Updates each item's dynamic nodes individually

This is the one place where diffing is unavoidable — but it's diffing a flat list of keys, not a deep tree of nodes.

### Phase 5: Conditional Compilation

```canopy
view model =
    if model.loading then
        spinner []
    else
        content model.data
```

Compiles to a block-level swap: the compiler pre-compiles both branches as templates, and swaps them in/out based on the condition. Each branch has its own mount/update functions.

## What Changes in the Compiler

### New IR: Reactive Graph

Between `AST.Optimized` and `Generate.JavaScript`, add a new intermediate representation:

```haskell
data ReactiveNode
  = StaticTemplate Builder    -- cloneNode, no updates needed
  | DynamicText [ModelPath]   -- textContent update
  | DynamicAttr Attr [ModelPath]  -- attribute update
  | ConditionalBlock [ModelPath] ReactiveNode ReactiveNode
  | ListBlock [ModelPath] ReactiveNode
  | ComponentMount ModuleName
```

The `ModelPath` type tracks which fields of the model each node depends on (e.g., `["count"]`, `["user", "name"]`).

### Analysis Pass

New module: `Optimize/Reactive.hs`

1. Walk the `view` function's AST
2. For each `Html` node constructor, determine if arguments are static or model-dependent
3. Build the `ReactiveNode` tree
4. Compute dependency sets for each dynamic node

### Code Generation

New module: `Generate/JavaScript/Reactive.hs`

Takes the `ReactiveNode` tree and emits:
- Template strings for static subtrees
- Mount function with `cloneNode` + event listener attachment
- Update function with per-field change checks

## Backward Compatibility

- `Html.lazy` continues to work (it's a hint to the reconciler, and the reactive compiler can use it as a component boundary)
- The VDOM path remains available as a fallback for patterns the reactive compiler can't analyze
- `--reactive` flag enables the new codegen (default once stable)

## Performance Targets

| Metric | Current (VDOM) | Target (Reactive) |
|--------|---------------|-------------------|
| Create 1K rows | ~30 ops/sec | >40 ops/sec |
| Update 1K rows | ~25 ops/sec | >35 ops/sec |
| Bundle size (hello world, gzip) | ~19 KB | < 2 KB |
| Startup time | ~50ms | < 30ms |

## Risks

- **Complex view functions**: Some `view` functions use higher-order composition that makes static analysis difficult. Solution: fall back to VDOM for those subtrees.
- **Third-party Html libraries**: Code that constructs Html outside the view function may not be analyzable. Solution: treat unknown Html values as fully dynamic.
- **Structural equality**: Elm-style structural equality can't cheaply detect "same reference." Solution: use field-level comparison (if `model.count` didn't change, skip that update).
