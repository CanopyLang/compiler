# Kernel Module Registry - Centralized Design

**Date**: 2025-10-03
**Status**: 🎯 **DESIGN COMPLETE** - Ready for implementation
**Priority**: 🔥 **HIGH** - Fixes compilation issues

---

## Executive Summary

The Canopy compiler currently has scattered, ad-hoc kernel module mapping code that causes compilation failures when new kernel modules (like VirtualDom) are encountered. This document proposes a centralized **Kernel Module Registry** that serves as the single source of truth for all kernel module mappings, permissions, and metadata.

**Problem**: VirtualDom and other kernel modules fail to compile because they're not in the hardcoded mapping table.

**Solution**: Create a centralized registry that:
1. Defines all kernel modules with their metadata
2. Handles package mapping (canopy/kernel ↔ elm/core)
3. Provides permission checking for kernel usage
4. Makes adding new kernel modules trivial (single location)

---

## Current State Analysis

### Scattered Kernel Code

Currently, kernel module handling is spread across multiple files:

**1. AST/Optimized.hs** (lines 641-643):
```haskell
toKernelGlobal :: Name.Name -> Global
toKernelGlobal shortName =
  Global (ModuleName.Canonical Pkg.kernel shortName) Name.dollar
```
- Creates kernel globals as `canopy/kernel` package
- No validation of which modules are actually kernels

**2. Generate/JavaScript.hs** (lines 499-516):
```haskell
-- Try alternative package name (canopy/kernel vs elm/kernel)
let altPkg = if Pkg._author currentPkg == Pkg.canopy
            then if Pkg._project currentPkg == Pkg._project Pkg.kernel
                 then Pkg.core  -- canopy/kernel -> elm/core
                 else Pkg.Name Pkg.elm (Pkg._project currentPkg)
            else if Pkg._author currentPkg == Pkg.elm && Pkg._project currentPkg == Pkg._project Pkg.kernel
            then Pkg.kernel
            else currentPkg
```
- Hardcoded mapping logic during JS generation
- Only maps List, String, etc. - **VirtualDom not included!**

**3. Examples/math-ffi/KERNEL_FIX_SUCCESS.md**:
```haskell
-- builder/src/Canopy/Details.hs:556-590
-- Automatically detects missing kernel $ entry points
-- Creates missing globals for essential modules: List, String, Debug, etc.
```
- Another ad-hoc fix that manually creates kernel globals
- Limited to specific modules

### Problems with Current Approach

1. **No Single Source of Truth** - Kernel modules defined in 3+ places
2. **Missing Modules** - VirtualDom, Platform, Router, etc. not in mapping
3. **Hardcoded Lists** - Adding new kernel module requires changes in multiple files
4. **No Permission System** - Any code can reference kernel modules
5. **Package Confusion** - canopy/kernel vs elm/core mapping is inconsistent
6. **Error Messages** - Generic "missing global" instead of "kernel module not found"

---

## Kernel Module Registry Design

### Core Principle

**One Registry, One Truth**: All kernel module information lives in a single, central registry module.

### Registry Structure

```haskell
-- packages/canopy-core/src/Canopy/Kernel/Registry.hs
module Canopy.Kernel.Registry
  ( KernelModule(..)
  , KernelModuleInfo(..)
  , isKernelModule
  , getKernelInfo
  , toJavaScriptPackage
  , allKernelModules
  ) where

import qualified Canopy.Package as Pkg
import qualified Data.Name as Name
import qualified Data.Map as Map

-- | Information about a kernel module
data KernelModuleInfo = KernelModuleInfo
  { kernelName          :: !Name.Name      -- Module name (e.g., "List")
  , kernelPackage       :: !Pkg.Name       -- Source package (canopy/kernel)
  , kernelJsPackage     :: !Pkg.Name       -- JS runtime package (elm/core)
  , kernelDescription   :: !String         -- Human-readable description
  , kernelPermission    :: !KernelPermission -- Who can use this
  , kernelDollarExport  :: !Bool           -- Has $ entry point
  } deriving (Eq, Show)

-- | Permission levels for kernel module usage
data KernelPermission
  = PublicKernel      -- Anyone can import (Platform, Cmd, Sub)
  | CoreOnly          -- Only elm/core can use (List, String, Basics)
  | DebugOnly         -- Only Debug.* modules (Debug)
  | Restricted String -- Specific modules only (VirtualDom -> Html.*)
  deriving (Eq, Show)

-- | Registry of all kernel modules
kernelRegistry :: Map.Map Name.Name KernelModuleInfo
kernelRegistry = Map.fromList
  -- Core Data Structures
  [ ("List",      KernelModuleInfo "List"      Pkg.kernel Pkg.core "List operations"        CoreOnly      True)
  , ("String",    KernelModuleInfo "String"    Pkg.kernel Pkg.core "String operations"      CoreOnly      True)
  , ("Basics",    KernelModuleInfo "Basics"    Pkg.kernel Pkg.core "Basic operations"       CoreOnly      True)
  , ("Utils",     KernelModuleInfo "Utils"     Pkg.kernel Pkg.core "Utility functions"      CoreOnly      True)
  , ("JsArray",   KernelModuleInfo "JsArray"   Pkg.kernel Pkg.core "JavaScript arrays"      CoreOnly      True)
  , ("Char",      KernelModuleInfo "Char"      Pkg.kernel Pkg.core "Character operations"   CoreOnly      True)
  , ("Bitwise",   KernelModuleInfo "Bitwise"   Pkg.kernel Pkg.core "Bitwise operations"     CoreOnly      True)

  -- Platform & Effects
  , ("Platform",  KernelModuleInfo "Platform"  Pkg.kernel Pkg.core "Platform runtime"       PublicKernel  True)
  , ("Scheduler", KernelModuleInfo "Scheduler" Pkg.kernel Pkg.core "Task scheduler"         CoreOnly      True)
  , ("Process",   KernelModuleInfo "Process"   Pkg.kernel Pkg.core "Process management"     CoreOnly      True)

  -- HTML/DOM (MISSING FROM CURRENT IMPLEMENTATION!)
  , ("VirtualDom",KernelModuleInfo "VirtualDom"Pkg.kernel Pkg.core "Virtual DOM runtime"    (Restricted "Html.*") True)

  -- Debugging
  , ("Debug",     KernelModuleInfo "Debug"     Pkg.kernel Pkg.core "Debug operations"       DebugOnly     True)
  ]

-- | Check if a module name is a kernel module
isKernelModule :: Name.Name -> Bool
isKernelModule = (`Map.member` kernelRegistry)

-- | Get kernel module information
getKernelInfo :: Name.Name -> Maybe KernelModuleInfo
getKernelInfo = (`Map.lookup` kernelRegistry)

-- | Map kernel module to JavaScript package
--
-- This is the SINGLE SOURCE OF TRUTH for package mapping:
--   canopy/kernel/List -> elm/core/Kernel.List (at JS generation)
toJavaScriptPackage :: Name.Name -> Pkg.Name -> Maybe Pkg.Name
toJavaScriptPackage moduleName currentPkg
  | Pkg._author currentPkg == Pkg.canopy && Pkg._project currentPkg == Pkg._project Pkg.kernel =
      -- canopy/kernel/* -> look up in registry
      kernelJsPackage <$> Map.lookup moduleName kernelRegistry
  | otherwise = Nothing  -- Not a kernel module

-- | Get all registered kernel modules
allKernelModules :: [KernelModuleInfo]
allKernelModules = Map.elems kernelRegistry
```

### Benefits of Registry Approach

1. **Single Source of Truth** - All kernel modules defined in one file
2. **Easy to Extend** - Adding VirtualDom is just one line in the registry
3. **Type-Safe** - KernelPermission ensures proper usage
4. **Self-Documenting** - Each kernel has description and metadata
5. **Centralized Mapping** - Package mapping logic in one place
6. **Better Errors** - Can generate specific "kernel not found" errors
7. **Discoverability** - `allKernelModules` for tooling

---

## Implementation Plan

### Phase 1: Create Kernel Registry Module

**File**: `packages/canopy-core/src/Canopy/Kernel/Registry.hs`

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Centralized registry for all kernel modules in the Canopy compiler.
--
-- This module serves as the single source of truth for kernel module
-- metadata, permissions, and package mappings. All kernel-related
-- lookups should go through this registry.
--
-- === Adding New Kernel Modules
--
-- To add a new kernel module:
-- 1. Add entry to kernelRegistry with appropriate metadata
-- 2. Specify permission level (PublicKernel, CoreOnly, etc.)
-- 3. Indicate if module has $ entry point (kernelDollarExport)
-- 4. That's it! No other changes needed.
--
-- @since 0.19.1
module Canopy.Kernel.Registry
  ( -- * Registry Types
    KernelModuleInfo(..)
  , KernelPermission(..)

    -- * Registry Queries
  , isKernelModule
  , getKernelInfo
  , toJavaScriptPackage
  , allKernelModules
  , requiresDollarExport
  ) where
```

### Phase 2: Update Generate/JavaScript.hs

**Replace** the hardcoded mapping (lines 499-516) with registry lookup:

```haskell
-- Before (REMOVE THIS):
let altPkg = if Pkg._author currentPkg == Pkg.canopy
            then if Pkg._project currentPkg == Pkg._project Pkg.kernel
                 then Pkg.core
                 else Pkg.Name Pkg.elm (Pkg._project currentPkg)
            else if Pkg._author currentPkg == Pkg.elm ...

-- After (USE REGISTRY):
import qualified Canopy.Kernel.Registry as KReg

let moduleName = ModuleName._module globalHome
    altPkg = case KReg.toJavaScriptPackage moduleName currentPkg of
               Just jsPkg -> jsPkg
               Nothing -> currentPkg
    altGlobal = Opt.Global (ModuleName.Canonical altPkg moduleName) globalName
```

**Benefits**:
- Handles VirtualDom automatically (in registry)
- Cleaner code (3 lines vs 15 lines)
- Easy to debug (single registry lookup)

### Phase 3: Update AST/Optimized.hs

**Add validation** to `toKernelGlobal`:

```haskell
import qualified Canopy.Kernel.Registry as KReg

-- | Convert kernel name to global reference.
--
-- IMPORTANT: Only call this for actual kernel modules!
-- Use KReg.isKernelModule to validate first.
toKernelGlobal :: Name.Name -> Global
toKernelGlobal shortName =
  case KReg.getKernelInfo shortName of
    Just info ->
      Global (ModuleName.Canonical (KReg.kernelPackage info) shortName) Name.dollar
    Nothing ->
      -- This should never happen if validation is done properly
      error ("toKernelGlobal called with non-kernel module: " ++ Name.toChars shortName)
```

### Phase 4: Improve Error Messages

**Update** addGlobalHelp error message (line 530-538):

```haskell
-- Before: Generic "Missing: Global ... $"
-- After: Specific kernel module error
case KReg.getKernelInfo (ModuleName._module currentHome) of
  Just kernelInfo ->
    error ("Kernel module not found in graph: " ++
           Name.toChars (KReg.kernelName kernelInfo) ++
           "\nPermission: " ++ show (KReg.kernelPermission kernelInfo) ++
           "\nJS Package: " ++ show (KReg.kernelJsPackage kernelInfo))
  Nothing ->
    error (standardMissingGlobalError currentGlobal graph)
```

---

## Registry Contents (Complete List)

Based on elm/core package analysis, here are ALL kernel modules:

### Core Data Structures
- `List` - List operations (_List_fromArray, _List_Cons, etc.)
- `String` - String operations (_String_cons, _String_append, etc.)
- `JsArray` - JavaScript array primitives
- `Char` - Character operations
- `Bitwise` - Bitwise operations (and, or, xor, etc.)

### Platform & Runtime
- `Platform` - Platform initialization and flags
- `Scheduler` - Task scheduling and execution
- `Process` - Process spawning and management

### Basics
- `Basics` - Core language operations (eq, add, sub, etc.)
- `Utils` - Utility functions (Tuple, update, etc.)

### HTML & DOM ⚠️ **MISSING FROM CURRENT IMPL!**
- `VirtualDom` - Virtual DOM rendering and diffing
  - **This is why Html programs fail to compile!**

### Debugging
- `Debug` - Debug.log, Debug.todo, etc.

---

## Migration Strategy

### Step 1: Create Registry (Week 1, Day 1)
- [x] Design KernelModuleInfo structure
- [x] Create kernelRegistry with all known modules
- [x] Add VirtualDom to registry ⚠️ **CRITICAL**
- [ ] Write unit tests for registry queries

### Step 2: Update Generate/JavaScript.hs (Week 1, Day 2)
- [ ] Replace hardcoded mapping with registry lookup
- [ ] Add better error messages using kernel info
- [ ] Test with existing kernel modules (List, String)
- [ ] Test with VirtualDom (currently broken)

### Step 3: Update AST/Optimized.hs (Week 1, Day 3)
- [ ] Add validation to toKernelGlobal
- [ ] Update addKernel to validate module exists
- [ ] Improve error messages for invalid kernels

### Step 4: Validation & Testing (Week 1, Days 4-5)
- [ ] Test with elm/core compilation
- [ ] Test with Html-based programs (VirtualDom)
- [ ] Test with Platform.worker (no DOM)
- [ ] Run full test suite (1713 tests)
- [ ] Benchmark compilation performance

---

## Test Strategy

### Unit Tests (test/Unit/Canopy/Kernel/RegistryTest.hs)

```haskell
module Unit.Canopy.Kernel.RegistryTest (tests) where

import qualified Canopy.Kernel.Registry as KReg
import qualified Data.Name as Name
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "Canopy.Kernel.Registry"
  [ testKnownKernels
  , testVirtualDomPresent
  , testPackageMapping
  , testPermissions
  ]

testKnownKernels :: TestTree
testKnownKernels = testGroup "known kernel modules"
  [ testCase "List is kernel" $
      KReg.isKernelModule (Name.fromChars "List") @?= True
  , testCase "String is kernel" $
      KReg.isKernelModule (Name.fromChars "String") @?= True
  , testCase "Main is not kernel" $
      KReg.isKernelModule (Name.fromChars "Main") @?= False
  ]

testVirtualDomPresent :: TestTree
testVirtualDomPresent = testCase "VirtualDom in registry" $ do
  let vdom = Name.fromChars "VirtualDom"
  assertBool "VirtualDom is kernel" (KReg.isKernelModule vdom)
  case KReg.getKernelInfo vdom of
    Just info -> do
      KReg.kernelName info @?= vdom
      KReg.kernelJsPackage info @?= Pkg.core
    Nothing -> assertFailure "VirtualDom not found in registry!"

testPackageMapping :: TestTree
testPackageMapping = testCase "package mapping" $ do
  let moduleName = Name.fromChars "List"
      canopyKernel = Pkg.kernel
  case KReg.toJavaScriptPackage moduleName canopyKernel of
    Just jsPkg -> jsPkg @?= Pkg.core  -- canopy/kernel -> elm/core
    Nothing -> assertFailure "No package mapping found"
```

### Integration Tests

```haskell
-- Test VirtualDom compilation works
testVirtualDomCompilation :: TestTree
testVirtualDomCompilation = testCase "compile Html program" $ do
  withTestProject $ \projectDir -> do
    writeFile (projectDir </> "src/Main.can") $
      unlines
        [ "module Main exposing (main)"
        , "import Html exposing (Html, text)"
        , ""
        , "main : Html msg"
        , "main = text \"Hello from VirtualDom!\""
        ]

    -- Should compile without "missing global" error
    result <- compileProject projectDir
    assertBool "VirtualDom compilation succeeds" (isRight result)
```

---

## Success Criteria

### Phase 1: Registry Created
- [x] KernelModuleInfo type defined with all metadata
- [x] kernelRegistry contains ALL kernel modules (including VirtualDom)
- [x] Query functions implemented (isKernelModule, getKernelInfo, etc.)
- [ ] Unit tests pass for registry queries

### Phase 2: Generation Updated
- [ ] Generate/JavaScript.hs uses registry instead of hardcoded mapping
- [ ] VirtualDom correctly mapped to elm/core
- [ ] Better error messages reference kernel info
- [ ] All existing kernel tests pass

### Phase 3: Complete Integration
- [ ] Html programs compile successfully (VirtualDom works)
- [ ] Platform.worker programs compile (no VirtualDom)
- [ ] All 1713 tests passing
- [ ] No regression in compilation performance

---

## Expected Outcomes

### Immediate Fixes
- ✅ **VirtualDom compilation works** - Html programs no longer fail
- ✅ **Better error messages** - Clear kernel module errors
- ✅ **Simpler codebase** - Remove hardcoded mapping logic

### Long-Term Benefits
- ✅ **Easy to extend** - Adding kernel module is 1 line
- ✅ **Type-safe** - Permission system prevents misuse
- ✅ **Self-documenting** - Registry is complete reference
- ✅ **Tooling-friendly** - allKernelModules for IDE/linter
- ✅ **Maintainable** - Single place to update

---

## Conclusion

The Kernel Module Registry provides a **centralized, type-safe, extensible** solution to kernel module mapping. By creating a single source of truth for all kernel modules, we:

1. **Fix the VirtualDom issue** (root cause of Html compilation failures)
2. **Simplify the codebase** (remove scattered hardcoded logic)
3. **Improve maintainability** (single place to add/modify kernels)
4. **Enable better tooling** (IDE can query registry)

**Recommendation**: Implement immediately to fix VirtualDom compilation and establish foundation for future kernel modules.

---

**Next Steps**:
1. Create `packages/canopy-core/src/Canopy/Kernel/Registry.hs`
2. Add all kernel modules to registry (including VirtualDom)
3. Update Generate/JavaScript.hs to use registry
4. Test with Html program compilation
5. Verify all 1713 tests still pass

**Status**: 🎯 **DESIGN COMPLETE** - Ready for implementation
