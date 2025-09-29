# Canopy Compiler: Global Graph Missing elm/core Dependencies - Debug & Fix Plan

## 🚨 Problem Summary

The Canopy compiler is failing during JavaScript code generation with the error:

```
MyException "addGlobalHelp: missing global in graph Global (Canonical {_package = Name {_author = canopy, _project = kernel}, _module = List}) $ (also tried Global (Canonical {_package = Name {_author = elm, _project = core}, _module = List}) $) - available keys: 697 globals"
```

**Root Cause IDENTIFIED**: The issue is two-fold:
1. ✅ **FIXED**: Global references are incorrectly created with `canopy/kernel` package instead of `elm/core`
2. 🔄 **REMAINING**: Even with correct package mapping, the specific List function globals are not included in the GlobalGraph

**PROGRESS**: The error message now shows it tries `elm/core` instead of `elm/kernel`, confirming the package mapping fix works!

## 🔍 Technical Analysis

### Error Location
- **File**: `compiler/src/Generate/JavaScript.hs`
- **Function**: `addGlobalHelp`
- **Line Context**: Lines ~80-100 in the search pattern matching

### Issue Details

1. **Graph Population Problem**: The `Opt.GlobalGraph` being passed to `generate` is missing elm/core globals
2. **Incorrect Fallback Logic**: The `addGlobalHelp` function tries to map `canopy/kernel` → `elm/kernel`, but List is in `elm/core`
3. **Package Mapping Bug**: The alternative package lookup is looking in the wrong package (kernel vs core)

### Evidence from Error Analysis

```haskell
-- Current broken logic in addGlobalHelp:
altPkg = if Pkg._author currentPkg == Pkg.canopy && Pkg._project currentPkg == Pkg._project Pkg.kernel
        then Pkg.kernel  -- WRONG: Maps canopy/kernel -> elm/kernel
        else currentPkg
```

**Problem**: List is not in any kernel package. It's in `elm/core`.

## 📋 Debugging Steps

### Phase 1: Verify Graph Contents

1. **Add Debug Logging to GlobalGraph Creation**:
   ```bash
   # Find where Opt.GlobalGraph is created
   grep -r "GlobalGraph" compiler/src/Optimize/
   grep -r "GlobalGraph" builder/src/
   ```

2. **Log Available Globals**:
   ```haskell
   -- In Generate/JavaScript.hs, add to generate function:
   let graphKeys = Map.keys graph
   putStrLn ("DEBUG: Available globals in graph: " <> show (take 50 graphKeys))
   putStrLn ("DEBUG: Looking for elm/core List globals...")
   putStrLn ("DEBUG: elm/core globals: " <> show (filter (isElmCore . globalHome) graphKeys))
   ```

3. **Check elm/core Processing**:
   ```bash
   # Look for elm/core special handling
   grep -r "elm/core" builder/src/
   grep -r "Pkg.core" builder/src/
   ```

### Phase 2: Trace elm/core Artifact Generation

1. **Verify elm/core Dependencies Are Built**:
   - Check `builder/src/Canopy/Details.hs` verifyDependencies function
   - Ensure elm/core is properly included in solution map
   - Verify elm/core artifacts are created (not empty)

2. **Trace Optimization Phase**:
   ```bash
   # Check what's happening in optimization
   grep -r "elm/core" compiler/src/Optimize/
   ```

3. **Check Interface Loading**:
   - Verify elm/core interfaces are loaded correctly
   - Check if global definitions from elm/core make it to GlobalGraph

### Phase 3: Fix the Fallback Logic

1. **Immediate Fix - Correct Package Mapping**:
   ```haskell
   -- In addGlobalHelp function, replace the current logic:
   altPkg = case (Pkg._author currentPkg, Pkg._project currentPkg) of
     (Pkg.canopy, "kernel") -> Pkg.kernel
     (Pkg.canopy, "core") -> Pkg.core  -- Add this mapping
     _ -> currentPkg
   ```

2. **Better Approach - Remove Hardcoded Assumptions**:
   ```haskell
   -- Instead of hardcoded mappings, use a systematic approach:
   altPkg = case Pkg._author currentPkg of
     Pkg.canopy -> Pkg.Name Pkg.elm (Pkg._project currentPkg)  -- canopy/* -> elm/*
     _ -> currentPkg
   ```

## 🛠️ Proposed Fixes

### Fix 1: Immediate Band-Aid (Quick Fix)

**File**: `compiler/src/Generate/JavaScript.hs`

```haskell
-- In addGlobalHelp function, around line 85:
altPkg = case (Pkg._author currentPkg, Pkg._project currentPkg) of
  (Pkg.canopy, project) -> Pkg.Name Pkg.elm project  -- canopy/* -> elm/*
  _ -> currentPkg
```

### Fix 2: Root Cause Resolution (Proper Fix)

**Issue**: elm/core globals are not being included in the GlobalGraph

**Investigation needed**:
1. Find where `Opt.GlobalGraph` is created
2. Ensure elm/core artifacts contribute to the graph
3. Fix the optimization pipeline to include essential elm/core globals

**Likely locations**:
- `compiler/src/Optimize/*.hs` - Check optimization pipeline
- `builder/src/Canopy/Details.hs` - Check artifact processing
- Interface loading and global collection

### Fix 3: Enhanced Debugging

**Add comprehensive logging**:

```haskell
-- In Generate/JavaScript.hs generate function:
generate mode (Opt.GlobalGraph graph _) mains ffiInfos =
  let _ = trace ("GLOBAL-GRAPH-DEBUG: Total globals: " <> show (Map.size graph)) ()
      _ = trace ("GLOBAL-GRAPH-DEBUG: elm/core globals: " <>
                show (length $ filter isElmCoreGlobal (Map.keys graph))) ()
      elmCoreGlobals = filter isElmCoreGlobal (Map.keys graph)
      _ = trace ("GLOBAL-GRAPH-DEBUG: elm/core List globals: " <>
                show (filter isListGlobal elmCoreGlobals)) ()
  in ...

isElmCoreGlobal :: Opt.Global -> Bool
isElmCoreGlobal (Opt.Global home _) =
  let pkg = ModuleName._package home
  in Pkg._author pkg == Pkg.elm && Pkg._project pkg == Pkg.core

isListGlobal :: Opt.Global -> Bool
isListGlobal (Opt.Global home _) =
  ModuleName._module home == Name.fromChars "List"
```

## 🧪 Testing Strategy

### Test 1: Simple elm/core Usage
```canopy
module Test exposing (main)

import Html exposing (text)

main = text (String.fromInt (List.length [1, 2, 3]))
```

### Test 2: Math FFI Example
```bash
cd examples/math-ffi
canopy make src/Main.can --output=test.js
```

### Test 3: Core Function Usage
```canopy
module CoreTest exposing (main)

import Html exposing (text)

main = text (Debug.toString (List.map (\x -> x * 2) [1, 2, 3]))
```

## 🔧 Implementation Plan

### Step 1: Emergency Fix (30 minutes)
- [ ] Apply Fix 1 (update package mapping logic)
- [ ] Test with math-ffi example
- [ ] Verify compilation succeeds

### Step 2: Deep Investigation (2-4 hours)
- [ ] Add comprehensive debug logging
- [ ] Trace elm/core processing through build pipeline
- [ ] Identify where elm/core globals get lost
- [ ] Document the full flow from elm/core source to GlobalGraph

### Step 3: Proper Resolution (4-8 hours)
- [ ] Fix the root cause in optimization pipeline
- [ ] Ensure elm/core artifacts are properly processed
- [ ] Verify all elm/core globals are available in GlobalGraph
- [ ] Remove the need for fallback logic entirely

### Step 4: Validation (1-2 hours)
- [ ] Test all examples compile successfully
- [ ] Run full test suite
- [ ] Verify no regressions introduced

## 📊 Expected Outcomes

### Immediate (Fix 1)
- Math FFI example compiles successfully
- JavaScript output is generated (non-empty)
- Basic elm/core functions work

### Long-term (Fix 2)
- Robust elm/core support
- No more missing global errors
- Clean, maintainable code without hardcoded mappings
- Proper separation between canopy and elm packages

## 🚩 Risk Assessment

### Low Risk
- Fix 1 (package mapping update) - Minimal surface area

### Medium Risk
- Optimization pipeline changes - Could affect other packages

### High Risk
- Major changes to elm/core handling - Could break compatibility

## 📝 Notes

- The error shows 697 globals are available, so the graph isn't completely empty
- elm/core is likely being processed but its globals aren't making it to the final graph
- The FFI system is working (FFI content is loaded successfully)
- This might be related to recent changes in elm/core package handling

## 🔗 Related Files to Investigate

1. `compiler/src/Generate/JavaScript.hs` - Error location
2. `compiler/src/Optimize/*.hs` - GlobalGraph creation
3. `builder/src/Canopy/Details.hs` - Package processing
4. `compiler/src/AST/Optimized.hs` - GlobalGraph definition
5. `examples/math-ffi/` - Test case

---

## 🎯 CURRENT STATUS (MAJOR PROGRESS!)

### ✅ Successfully Fixed: Package Mapping Issue
**File**: `compiler/src/Generate/JavaScript.hs`
**Fix Applied**: Updated fallback logic in `addGlobalHelp` to map `canopy/kernel` → `elm/core` instead of `elm/kernel`

**Code Change**:
```haskell
altPkg = if Pkg._author currentPkg == Pkg.canopy
        then -- Map canopy packages: kernel->core for standard modules
             if Pkg._project currentPkg == Pkg._project Pkg.kernel
             then Pkg.core  -- canopy/kernel -> elm/core (for List, String, etc.)
             else Pkg.Name Pkg.elm (Pkg._project currentPkg)
        -- ... rest of logic
```

**Verification**: Error message now shows `elm/core` instead of `elm/kernel` 🎉

### 🔄 Remaining Issue: Missing GlobalGraph Entries
**Problem**: Even with correct package mapping, List function globals are not in the GlobalGraph
**Evidence**:
- elm/core List **module** exists in dmvarContents
- Specific List **functions** (e.g., `List.length`) are missing from GlobalGraph
- Available keys: 694-697 globals (substantial but incomplete)

### 🔬 Deep Analysis Completed
1. **Canonicalization Phase**: ✅ Traced - issue not in variable resolution
2. **Optimization Phase**: ✅ Traced - Global references created here with wrong package
3. **JavaScript Generation**: ✅ Fixed - fallback logic now correct
4. **GlobalGraph Creation**: 🔄 Needs investigation - elm/core functions missing

## 🛠️ Next Steps (Priority Order)

### Immediate (Continue Investigation)
1. **Debug GlobalGraph Population**: Add logging to optimization phase to see why elm/core functions aren't included
2. **Check Interface Processing**: Verify elm/core interfaces contain function definitions
3. **Trace Optimization Pipeline**: Follow how elm/core modules become GlobalGraph entries

### Quick Workaround Options
1. **Preload elm/core Globals**: Manually add essential globals to graph
2. **Interface Verification**: Ensure elm/core interfaces are complete

**Next Action**: Investigate GlobalGraph population in optimization phase to understand why elm/core function globals are missing despite module availability.