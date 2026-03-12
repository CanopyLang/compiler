# P03: TypeScript Interop

## Priority: HIGH -- Phase 2 (Adoption Enabler)
## Effort: 1-2 weeks remaining (ARIA + integration tests only)
## Status: Pipeline wired, bugs fixed -- 2 tasks remain

## Post-Remediation Status (2026-03-12)

The audit remediation completed all pipeline wiring and bug fixes. Only ARIA integration and end-to-end integration tests remain.

| Component | Code Exists? | Wired Into Build? | Working? |
|-----------|-------------|-------------------|----------|
| .d.ts generation | Yes (4 modules) | **Yes** | **Yes** |
| FFI TypeScript validation | Yes (181 lines) | **Yes** | **Yes** |
| .d.ts parser | Yes (320 lines) | **Yes** (npm pipeline) | **Yes** |
| npm module resolution | Yes (363 lines) | **Yes** (NpmPipeline.hs) | **Yes** |
| JS wrapper generation | Yes (199 lines) | **Yes** (NpmPipeline.hs) | **Yes** (bug fixed) |
| Web Component generation | Yes (315 lines) | **Yes** (Kit/Build.hs) | **Yes** (leak fixed) |
| ARIA/form integration | **No** | N/A | N/A |

### Bugs Fixed (Audit Remediation)
1. `NpmWrapper.hs` line 184: `UnwrapMaybe` now generates `'a' in p0 ? p0.a : null` (valid across dev/prod)
2. `WebComponent.hs`: `disconnectedCallback` now unsubscribes all port handlers via `this._handlers`
3. `FFI/NpmPipeline.hs` created: chains resolve -> parse .d.ts -> type map -> generate wrapper

## What's Done

### .d.ts Generation (100% complete)

- `Generate/TypeScript.hs` -- Main orchestrator
- `Generate/TypeScript/Convert.hs` -- Canopy->TypeScript type conversion
- `Generate/TypeScript/Render.hs` -- .d.ts file rendering
- `Generate/TypeScript/Types.hs` -- TypeScript AST types
- Tests: 34 unit + 6 golden

### FFI TypeScript Validation (100% complete)

- `FFI/TypeScriptValidation.hs` (181 lines) -- validates FFI sigs match .d.ts
- 32 tests

### .d.ts Parser (100% complete, fully used)

- `Generate/TypeScript/Parser.hs` (320 lines) -- parses function/interface/type/const exports
- Used by validator AND npm wrapper pipeline

### npm Wrapper Pipeline (100% wired)

- `FFI/NpmPipeline.hs` (~130 lines) -- orchestrates resolve -> parse -> map -> generate
- Type mapping: TsUnion->UnwrapMaybe, TsObject->UnwrapNewtype, TsVoid->ReturnCmd, Promise->WrapPromise
- 17 unit tests in `NpmPipelineTest.hs`

### Web Component Generation (100% wired)

- `Generate/JavaScript/WebComponent.hs` -- generates Custom Element class with Shadow DOM
- Called from `Kit/Build.hs` for modules listed in `_appWebComponents`
- Port handler lifecycle: subscribe in connected, unsubscribe in disconnected
- 11 unit tests in `WebComponentTest.hs`

## What Remains

### Task 1: ARIA and form integration (2 days)

Not implemented at all. Needed for accessible Web Components.

Steps:
1. Forward `role`, `aria-*` attributes from host to shadow root
2. Add `static formAssociated = true` for form-participating elements
3. Implement `formStateRestoreCallback`

### Task 2: Integration tests + docs (1 week)

- Vite + TypeScript project consuming Canopy Web Components
- React project mounting `<my-canopy-counter>` with typed props
- npm package consumption test (date-fns format function)
- Update `typescript-interop.md` with Phase 2-4 examples

## Definition of Done

- [x] .d.ts files generated automatically alongside .js
- [x] Full type mapping (Int, String, Bool, List, Maybe, Result, Dict, records, custom types)
- [x] Web Component HTMLElementTagNameMap augmentation
- [x] 34 unit + 6 golden tests for .d.ts
- [x] FFI TypeScript validation (32 tests)
- [x] npm FFI imports -> resolved, validated, wrapper generated **in build pipeline**
- [x] Web Component generation **called from build pipeline** with typed attributes + events
- [x] Port unsubscription in disconnectedCallback (no memory leak)
- [ ] Promise->Task, nullable->Maybe, callback->Task conversions **tested end-to-end**
- [ ] ARIA attribute forwarding through Shadow DOM
- [ ] Integration tests: Canopy modules used from TypeScript project
- [ ] Integration tests: npm packages used from Canopy
