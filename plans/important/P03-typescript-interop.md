# P03: TypeScript Interop

## Priority: HIGH -- Phase 2 (Adoption Enabler)
## Effort: 3-4 weeks (Phases 2-4 remaining)
## Depends on: Nothing (Phase 1 complete, ESM output complete)

## Status Overview

Phase 1 (.d.ts generation) is **100% complete** and production-ready. FFI TypeScript validation is done. Basic Web Component generation exists. Phases 2-4 (npm package consumption, enhanced Web Components, integration testing) remain and are the critical path for the gradual adoption story.

| Phase | Status | Effort Remaining |
|-------|--------|------------------|
| Phase 1: .d.ts generation | DONE | 0 |
| FFI TypeScript validation | DONE | 0 |
| Basic Web Component generation | DONE | 0 |
| Phase 2: npm package consumption | NOT STARTED | 1.5-2 wks |
| Phase 3: Enhanced Web Components | NOT STARTED | 1-1.5 wks |
| Phase 4: Integration testing + docs | NOT STARTED | 0.5-1 wk |

## What's Done (with file references)

### Phase 1: .d.ts Generation (100% complete)

- **`Generate/TypeScript.hs`** -- Main orchestrator, auto-generates .d.ts alongside .js on build
- **`Generate/TypeScript/Convert.hs`** -- Canopy-to-TypeScript type conversion logic
- **`Generate/TypeScript/Render.hs`** -- .d.ts file rendering with proper formatting
- **`Generate/TypeScript/Types.hs`** -- TypeScript AST types used during generation
- **`Generate/TypeScript/WellKnown.hs`** -- Standard type conversions (String->string, Int->number, etc.)

Type mapping (all implemented):

| Canopy Type | TypeScript Type |
|-------------|----------------|
| `String` | `string` |
| `Int` | `number` |
| `Float` | `number` |
| `Bool` | `boolean` |
| `List a` | `ReadonlyArray<A>` |
| `Maybe a` | `{ $: 'Just', a: A } \| { $: 'Nothing' }` |
| `Result e a` | `{ $: 'Ok', a: A } \| { $: 'Err', a: E }` |
| `Dict k v` | `ReadonlyMap<K, V>` |
| Record `{ x : Int }` | `{ readonly x: number }` |
| Custom type | Discriminated union with `$` tag |
| Opaque type | Opaque branded type |

Tests: 34 unit tests + 6 golden tests.

### FFI TypeScript Validation (complete)

- **`FFI/TypeScriptValidation.hs`** (181 lines) -- Validates that FFI type signatures match their TypeScript declarations
- 32 tests covering type mismatch detection, nullable handling, generic validation

### Basic Web Component Generation (complete)

- **`Generate/JavaScript/WebComponent.hs`** (177 lines) -- Generates Web Component class extending HTMLElement
- HTMLElementTagNameMap augmentation in .d.ts output
- Shadow DOM mounting, observedAttributes, attributeChangedCallback

## What Remains

### Phase 2: npm Package Consumption (1.5-2 weeks)

Enable Canopy code to consume npm packages with type safety by reading `.d.ts` files:

```canopy
foreign import javascript "./node_modules/date-fns/format.d.ts"
    format : Posix -> String -> String
```

The compiler:
1. Reads the `.d.ts` file
2. Validates the Canopy type signature matches the TypeScript type
3. Generates the JS binding wrapper
4. Wraps results in appropriate Canopy types (nullable -> Maybe, union -> Result, etc.)

Implementation:
- Minimal `.d.ts` parser (does not need full TypeScript parser -- only needs to handle exported function signatures, interfaces, and type aliases)
- Wrapper generation for common patterns: Promise -> Task, callback -> Cmd, nullable -> Maybe, optional params -> Maybe
- Warning/error system for unsupported TypeScript features (conditional types, mapped types, template literal types)

### Phase 3: Enhanced Web Components (1-1.5 weeks)

Build on the existing `WebComponent.hs` to add:
- Attribute type validation (string attributes mapped to Canopy types)
- Two-way property binding for form elements
- ARIA attribute forwarding through Shadow DOM
- Named slot support with typed slot content
- Event dispatching from Canopy to host (CustomEvent with typed detail)

### Phase 4: Integration Testing and Documentation (0.5-1 week)

- Integration tests: use Canopy modules from a TypeScript project (Vite + TS)
- Integration tests: use npm packages from Canopy (date-fns, zod, etc.)
- Integration tests: mount Canopy Web Components in React, Vue, Svelte
- Migration guide: "Using Canopy in an Existing React Project"
- Guide: "Consuming npm Packages from Canopy"
- Example apps: Canopy component in Next.js, Canopy component in SvelteKit

## The Gradual Adoption Story

This is how teams adopt Canopy without rewriting:

1. **Week 1**: Add Canopy to existing React/Next.js project via Vite plugin
2. **Week 2**: Write one utility module in Canopy, import from TypeScript (Phase 1 enables this today)
3. **Month 1**: Extract business logic into Canopy modules (type-safe, zero runtime errors)
4. **Month 3**: Build new features as Canopy components, expose as Web Components (Phase 3)
5. **Month 6**: Core application logic in Canopy, React used only as a shell
6. **Month 12**: Full migration to CanopyKit

This is TypeScript's playbook adapted for a functional language.

## Dependencies

- Phase 1 (DONE) depends on ESM output (DONE)
- Phases 2-4 have no external dependencies
- CanopyKit benefits from Phase 3 (Web Components) but does not block it

## Risks

- **Type mapping fidelity**: Some TypeScript types (conditional types, mapped types, template literals) have no Canopy equivalent. These must be handled gracefully (warn, use opaque type).
- **Runtime representation**: The discriminated union encoding (`{ $: 'Tag', ... }`) must be stable and documented. Changing it would break TS consumers.
- **Web Component limitations**: Shadow DOM has known issues with forms, ARIA, and SSR. Document these clearly.
- **.d.ts parser scope**: A full TypeScript parser is not needed and would be over-engineering. The minimal parser only needs to handle the subset of .d.ts that maps cleanly to Canopy types.

## Definition of Done

- [x] .d.ts files generated automatically alongside .js files on build
- [x] Full type mapping (Int, String, Bool, List, Maybe, Result, Dict, records, custom types, opaque types)
- [x] Web Component HTMLElementTagNameMap augmentation
- [x] 34 unit tests + 6 golden tests for .d.ts generation
- [x] FFI TypeScript validation (32 tests)
- [x] Basic Web Component generation (177 lines)
- [ ] npm .d.ts files can be read and validated against Canopy FFI signatures
- [ ] Wrapper generation for Promise -> Task, callback -> Cmd, nullable -> Maybe
- [ ] Enhanced Web Components with attribute validation, ARIA, slots, events
- [ ] Integration tests: Canopy modules used from TypeScript project
- [ ] Integration tests: npm packages used from Canopy
- [ ] Integration tests: Web Components mounted in React, Vue, Svelte
- [ ] Migration guide: "Using Canopy in an Existing React Project"
- [ ] At least 2 example apps demonstrating TypeScript interop
