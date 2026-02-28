# Plan 15: FFI Namespace Unification

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Medium — touches codegen and runtime

## Problem

FFI currently operates through two separate mechanisms:
1. Kernel modules (`VarKernel Name Name`) — the original Elm approach
2. Canopy FFI (`Effects = FFI`) — the new Canopy approach

These coexist but have different codegen paths, different validation rules, and different import semantics. This creates confusion for contributors and users.

### Key Files
- `packages/canopy-core/src/AST/Canonical/Types.hs`: `VarKernel` and `FFI` in `Effects`
- `packages/canopy-core/src/Generate/JavaScript/Expression.hs`: Dual codegen paths
- `packages/canopy-core/src/Canonicalize/Module/FFI.hs`: Canopy FFI validation
- `packages/canopy-core/src/Generate/JavaScript/FFIRuntime.hs`: Runtime generation

## Implementation Plan

### Step 1: Document the two systems

**File**: `docs/FFI_ARCHITECTURE.md` (NEW)

Document current state: when kernel modules are used (elm/core internals) vs when FFI is used (user code). Clarify the long-term direction.

### Step 2: Create unified FFI resolution

**File**: `packages/canopy-core/src/FFI/Resolve.hs` (NEW)

Single entry point that handles both kernel and user FFI:

```haskell
data FFIBinding
  = KernelBinding !Name !Name      -- Legacy kernel module
  | UserFFIBinding !FilePath !Name  -- Canopy FFI .js file

resolveFFI :: ModuleName -> Name -> Either FFIError FFIBinding
```

### Step 3: Unified codegen

Merge the two codegen paths into a single handler:

```haskell
generateFFICall :: FFIBinding -> [JsExpr] -> JsExpr
generateFFICall (KernelBinding mod name) args = ...
generateFFICall (UserFFIBinding path name) args = ...
```

### Step 4: Migration path for kernel modules

Create a migration guide and tooling to help convert kernel module usages to the new FFI system where appropriate. Core library packages (elm/core) will continue using kernel modules.

### Step 5: Tests

- Test kernel FFI resolution
- Test user FFI resolution
- Test unified codegen produces correct output
- Golden tests for both FFI paths

## Dependencies
- Plan 05 (FFI strict mode) should be done first
