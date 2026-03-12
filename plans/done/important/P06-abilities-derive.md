# Plan P06: Abilities System + Derive

## Priority: HIGH -- Tier 1
## Status: COMPLETE (v1 production-ready) -- ~90% complete
## Effort: 1-2 weeks remaining for v1.1 polish
## Depends on: Stable compiler (Tier 0 complete)
## Split from: Plan 26 (Language Ergonomics)

## What's Done

### Parser
- **`Parse/Declaration.hs`** (734L) -- `ability` and `impl` keywords, super-abilities, `deriving` clauses
- Uses `withIndent` + `checkAligned` pattern (same as `let`/`case`)

### Canonicalization
- **`Canonicalize/Ability.hs`** (350L) -- method validation, orphan rule enforcement, duplicate detection, coverage checking
- **`Canonicalize/Environment/Foreign.hs`** -- foreign ability loading from .elmi interfaces
- **`Canonicalize/Environment/Local.hs`** -- local ability method registration
- **`Canonicalize/Module.hs`** -- abilities canonicalized BEFORE values (ordering matters)
- `AbilityMethod` var type in `Env.Var` for ability method resolution

### Resolution
- **`Canonicalize/ResolveAbilities.hs`** (258L) -- post-solve AST rewrite converting method calls to impl dictionary accesses

### Type System
- **`Type/Ability.hs`** (220L) -- `AbilityConstraint`, validation
- **`Type/Constrain/Module.hs`** -- wired into constraint generation
- **`Type/Constrain/Expression.hs`** -- `AbilityMethodCall` generates `CForeign` constraint
- Ability methods added as let-bindings via `letAbilityMethods`

### AST
- `AbilityMethodCall` variant in `Can.Expr_` -- tags ability method references
- Canonical Module has `_abilities :: Map Name Ability` and `_impls :: [Impl]`

### Code Generation
- **`Generate/JavaScript/Ability.hs`** -- dictionary-passing JS dispatch
- **`Generate/JavaScript/ESM.hs`** -- ESM backend support
- **`Generate/JavaScript/CodeSplit/Generate.hs`** -- code-split backend support

### Optimization
- **`Optimize/Module.hs`** -- `addAbilities`, `addImpls` registration in dependency graph
- **`Optimize/Expression.hs`** -- handles `AbilityMethodCall` via `Names.registerFFI`
- **`Queries/Optimize.hs`** -- integrates `ResolveAbilities` before optimization pass

### Derive
- **`Optimize/Derive.hs`** (580L) -- JSON Encode/Decode (with options), Enum deriving
- Eq/Show deriving parsed but code generation not yet implemented

### Interface Serialization
- `.elmi` format includes `_ifaceAbilities` and `_ifaceImpls` fields
- Backward-compatible decoders for pre-P06 artifact format (commit `65bf402`)

### Tests (31+ dedicated, all passing)
- Parse tests: 8
- Canonicalize tests: 23
- AST tests: 3

## What Remains (v1.1 polish)

### 1. Eq/Show Code Generation (~5 hours)
- Eq deriving parsed, needs codegen in `Optimize/Derive.hs`
- Show deriving parsed, needs codegen
- Follow same pattern as JSON Encode/Decode derive

### 2. Auto-Register Built-in Abilities (~2 hours)
- Eq, Ord, Show not auto-registered in environment currently
- Need to be available without explicit import for built-in types

### 3. Transitive Super-Ability Constraints (~3 hours)
- Super-ability declarations are parsed and stored
- Transitive enforcement not yet implemented (e.g., `Ord` requiring `Eq`)
- Constraint solver needs to propagate super-ability requirements

### 4. User-Facing Documentation (~1 day)
- Abilities tutorial in `docs/website/src/guide/`
- Derive usage examples
- Migration guide from manual Encode/Decode boilerplate

## v1 Limitations (non-blocking, addressable incrementally in v2)

- Monomorphic ability calls only (polymorphic dispatch = v2)
- Built-in abilities (Eq, Ord, Show) not auto-registered in env (v1.1)
- Super-ability constraints not transitively enforced (v1.1)
- No custom derive macros (user-defined derive = future work)

## Dependencies

| Dependency | Status |
|---|---|
| Stable compiler (Tier 0) | COMPLETE |
| Plan 26a (Language Ergonomics) | COMPLETE |

## Definition of Done

- [x] `ability` and `impl` keywords parse and compile
- [x] Generic functions with ability constraints type-check correctly
- [x] `deriving (Encode, Decode)` generates correct JSON codecs
- [x] Enum deriving works
- [x] All existing tests pass (backward compatible)
- [x] Error messages for ability-related type errors are clear and helpful
- [x] Interface serialization includes abilities/impls with backward compatibility
- [x] Dictionary-passing JS code generation works across all backends
- [x] 31+ dedicated tests passing
- [ ] `deriving (Eq, Show)` generates correct implementations
- [ ] Built-in abilities (Eq, Ord, Show) auto-registered in environment
- [ ] Transitive super-ability constraints enforced
- [ ] User-facing documentation published
