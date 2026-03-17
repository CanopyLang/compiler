# Plan 34: FFI Compile-Time Type Safety

## Priority: HIGH -- Tier 2
## Status: NOT STARTED
## Effort: 4-6 weeks
## Depends on: P03 TypeScript Interop (COMPLETE), FFI system (mature, 92 files)

## What Already Exists

### Current FFI Validation Pipeline

```
foreign import javascript "external/file.js" as FFI
    -> Parse foreign import statement
    -> Load JS file, parse JSDoc annotations
    -> Extract @canopy-type, @capability, @canopy-bind
    -> FFI.TypeParser: parse type string to FFIType (O(n) tokenization)
    -> FFI.StaticAnalysis: analyze JS AST for type mismatches (939 lines)
    -> FFI.TypeValidator: compare FFIType vs .d.ts (if available)
    -> FFI.CapabilityEnforcement: validate capabilities vs canopy.json
    -> Generate JavaScript + optional runtime validators (--ffi-strict)
```

### What IS Validated at Compile Time
- Type string parsing (malformed @canopy-type is an error)
- Static JS analysis: mixed-type ops, nullable returns, missing return paths, loose equality, async/Task mismatches, Result tag construction, return consistency
- TypeScript validation (if .d.ts exists): parameter count, field names, nested types
- Capability enforcement against canopy.json declarations
- Path validation (no traversal attacks)

### What Is NOT Validated (Gaps)

| Gap | Impact | Description |
|-----|--------|-------------|
| **Opaque type brand safety** | HIGH | `Unverified` opaques have zero runtime/compile-time checks. A function declaring opaque return but returning raw data passes silently. |
| **TypeScript validation optional** | HIGH | If no `.d.ts` exists, cross-validation is skipped entirely. Silent pass. |
| **Arity mismatch** | HIGH | FFI function declared `Int -> String` but JS takes 2 params -- not caught. No validation that @param count matches type arity. |
| **Generic type variables unconstrained** | MEDIUM | `FFITypeVar` has no constraint system. `Task a b` with actual `Task String Never` passes. |
| **Binding mode target unverified** | MEDIUM | `@canopy-bind method fakeMethod` compiles fine, fails at runtime. |
| **Promise/Task convention unenforced** | MEDIUM | Task types assume `_Scheduler_succeed/fail` pattern but this isn't validated. |
| **Record field consistency** | LOW | Same field name with different types across modules isn't detected. |
| **Implicit coercions in conditionals** | LOW | JS `if (x)` truthy checks not flagged when type expects Bool. |

## Proposed Improvements

### Phase 1: Mandatory Type Annotations (Week 1)

**Problem**: FFI functions without `@canopy-type` are not type-checked at the FFI boundary.

**Solution**:
1. Make `@canopy-type` annotations **required** for all exported FFI functions
2. Compiler error (not warning) when an exported JS function lacks a type annotation
3. Add auto-generation of `@canopy-type` stubs from Canopy-side type signatures as a migration aid

**Implementation**:
- Update `Foreign.FFI.hs` to emit error when exported function has no `@canopy-type`
- Add `canopy ffi init <file.js>` CLI command that generates JSDoc stubs from `.can` signatures
- Provide migration path: `--ffi-warn-untyped` flag for gradual adoption

### Phase 2: Arity Validation (Week 1-2)

**Problem**: Declared Canopy type arity doesn't match JS function parameter count.

**Solution**:
1. Count parameters in JavaScript function definition (AST analysis)
2. Count arrows in `@canopy-type` annotation
3. Compare: if JS has N params, Canopy type must have exactly N arrows (or N-1 if last is return)
4. Special handling for: `@canopy-bind method` (implicit `this`), variadic functions, optional params

**Implementation**:
- Extend `FFI.StaticAnalysis.hs` with `validateArity` pass
- Parse JS function params from AST (already available in static analysis)
- Compare against `FFI.TypeParser.countArity`

### Phase 3: Opaque Type Safety (Weeks 2-3)

**Problem**: `OpaqueKind.Unverified` opaques provide zero guarantees.

**Solution**:
1. **Require brand declaration**: All opaque types must specify their kind:
   - `@canopy-type opaque:symbol MyType` -- Symbol-branded (recommended)
   - `@canopy-type opaque:class MyType` -- instanceof check
   - `@canopy-type opaque:tag MyType` -- Property tag check (e.g., `__type: "MyType"`)
2. **Validate brand in JS**: Static analysis checks that:
   - Symbol-branded opaques wrap values with `Symbol.for("canopy:MyType")`
   - Class-backed opaques use `new` or constructor
   - Tag-branded opaques set the `__type` property
3. **Eliminate `Unverified`**: Phase out over one release cycle

**Implementation**:
- Update `FFI/Types.hs` OpaqueKind to require explicit brand strategy
- Add static analysis passes in `FFI/StaticAnalysis.hs` for each brand strategy
- Warning for `Unverified`, error in next release

### Phase 4: Mandatory .d.ts for Public Packages (Weeks 3-4)

**Problem**: TypeScript validation only runs if `.d.ts` exists. Most packages don't provide one.

**Solution**:
1. Auto-generate `.d.ts` from `@canopy-type` annotations as part of build
2. If a hand-written `.d.ts` exists, validate it against generated one (detect drift)
3. For published packages: `.d.ts` is mandatory in package artifact

**Implementation**:
- New module `Generate/TypeScript/FromFFI.hs`: converts `FFIType` -> TypeScript declaration
- Extend build pipeline to generate `.d.ts` alongside `.js` output
- Add validation pass comparing generated vs hand-written `.d.ts`

### Phase 5: Generic Type Constraints (Week 4-5)

**Problem**: Type variables like `a` in FFI types are unconstrained.

**Solution**:
1. Add `@canopy-constraint` annotation:
   ```javascript
   // @canopy-type comparable -> comparable -> Bool
   // @canopy-constraint comparable : Comparable
   ```
2. Validate that constraint is propagated to Canopy-side type signature
3. Support built-in constraints: `Comparable`, `Appendable`, `Number`

**Implementation**:
- Extend `FFI/Types.hs` with constraint field on `FFITypeVar`
- Parse `@canopy-constraint` in `Foreign.FFI.hs`
- Validate constraints match Canopy-side in `Canonicalize.Module.FFI.hs`

### Phase 6: Binding Mode Validation (Week 5-6)

**Problem**: `@canopy-bind method X` doesn't verify X exists on the target.

**Solution**:
1. For `@canopy-bind method X`: check that the receiver type's `.d.ts` (if available) declares method X
2. For `@canopy-bind get/set X`: check property existence
3. For `@canopy-bind new X`: check constructor exists
4. This is best-effort (requires `.d.ts` for the target type)

**Implementation**:
- Extend `FFI/TypeValidator.hs` to look up method/property on target type in `.d.ts`
- Add specific error messages: "Method 'X' not found on type 'Y'"

### Phase 7: Enhanced Static Analysis (Week 6)

**Problem**: Current static analysis misses some JS anti-patterns.

**Additions**:
1. **Truthy/falsy detection**: Flag `if (x)` when type annotation says `Bool`
2. **typeof validation**: `typeof x === "string"` should match when type is `String`
3. **Promise chain validation**: Detect `.then()` chains and verify they match Task result type
4. **Object mutation tracking**: Flag cases where an object's fields are mutated after construction (violates immutability assumption)

## Definition of Done

- [ ] @canopy-type annotations mandatory for exported functions (with migration flag)
- [ ] Arity validation: JS param count matches type arrow count
- [ ] Opaque types require explicit brand strategy (no more Unverified)
- [ ] Auto-generated .d.ts from @canopy-type annotations
- [ ] .d.ts mandatory for published packages
- [ ] Generic type constraints via @canopy-constraint
- [ ] Binding mode target validation (best-effort with .d.ts)
- [ ] Enhanced static analysis (truthy/falsy, typeof, Promise chains)
- [ ] All existing 4,472+ tests pass
- [ ] New test cases for each validation pass

## Risks

- **Breaking changes**: Making @canopy-type mandatory will break packages that lack annotations. The `--ffi-warn-untyped` migration flag mitigates this.
- **False positives**: Arity validation may false-positive on variadic functions or functions with optional params. Need escape hatch annotation.
- **Performance**: Additional validation passes add to compile time. Profile and ensure < 5% slowdown.
- **Opaque brand migration**: Existing opaque types in 27 FFI files need brand annotations. Provide `canopy ffi migrate` tool.
