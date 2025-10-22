# Parse Cache Verification Report
## Deep Investigation Results

**Date:** 2025-10-20
**Agent:** Parse Cache Verifier
**Status:** CRITICAL ISSUES FOUND

---

## Executive Summary

**FINDING: The parse cache is NOT being used at runtime in the current system.**

Previous reports claimed successful integration, but deep code inspection reveals:
1. **Parse.Cache module DOES NOT EXIST**
2. The old Build.hs references it, but this file is NOT being compiled
3. The NEW query-based system has NO cache integration
4. Parse.fromByteString is being called directly **at least 4 times per compilation**

---

## 1. Critical Discovery: No Parse.Cache Module

### Investigation
```bash
# Search for Parse.Cache module
find /home/quinten/fh/canopy/packages -name "Cache.hs" -path "*/Parse/*"
# Result: NO FILES FOUND

# Check exposed modules in canopy-core.cabal
grep -A 100 "exposed-modules:" canopy-core.cabal
# Result: NO Parse.Cache in list
```

### Finding
**Parse.Cache module does not exist anywhere in the codebase.**

The exposed modules in `/home/quinten/fh/canopy/packages/canopy-core/canopy-core.cabal` include:
- Parse.Module ✓
- Parse.Expression ✓
- Parse.Declaration ✓
- Parse.Pattern ✓
- Parse.Type ✓
- Parse.Cache ✗ **MISSING**

Only `File.Cache` exists (for file I/O caching), but there is no `Parse.Cache` for AST caching.

---

## 2. Old Build.hs vs NEW System

### Old Build.hs (NOT USED)
**Location:** `/home/quinten/fh/canopy/builder/src/Build.hs`

This file imports and uses ParseCache:
```haskell
import qualified Parse.Cache as ParseCache

parseCacheMVar <- newMVar ParseCache.emptyCache
let (result, newCache) = ParseCache.cacheLookupOrParse path projectType source cache
```

**Problem:** This Build.hs is NOT part of the compiled system!

**Evidence:**
```bash
# Check what's actually being compiled
ls /home/quinten/fh/canopy/packages/canopy-terminal/src/Build.hs
# This is the real Build.hs - it's just a re-export wrapper

# The real build system is in:
# - canopy-driver (orchestration)
# - canopy-query (query system)
# - canopy-builder (compilation logic)
```

### NEW System Architecture
The actual compilation path is:
1. **Terminal** → calls Build.fromPaths
2. **Build.hs** (canopy-terminal) → wrapper, calls Compiler.compileFromPaths
3. **Compiler.hs** (canopy-builder) → orchestrates compilation
4. **Driver.hs** (canopy-driver) → query-based compilation
5. **Query/Simple.hs** (canopy-query) → executes parse queries

---

## 3. All Uncached Parse Locations

### 3.1 Query/Simple.hs (PRIMARY PARSE LOCATION)
**File:** `/home/quinten/fh/canopy/packages/canopy-query/src/Query/Simple.hs`
**Line:** 87

```haskell
executeQuery :: Query -> IO (Either QueryError QueryResult)
executeQuery query = case query of
  ParseModuleQuery path _ projectType -> do
    content <- BS.readFile path
    case Parse.fromByteString projectType content of  -- NO CACHE!
      Left err -> return $ Left $ ParseError path (show err)
      Right modul -> return $ Right $ ParsedModule modul
```

**Impact:** This is called for EVERY module parse in the NEW system.
**Cache Status:** ✗ NO CACHE

### 3.2 Compiler.hs Location #1
**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Compiler.hs`
**Line:** 163

```haskell
parseModuleFile projType path = do
  content <- BS.readFile path
  case Parse.fromByteString projType content of  -- NO CACHE!
    Left err -> error ("Failed to parse: " ++ path ++ "\nError: " ++ show err)
    Right m -> return m
```

**Context:** Used in `discoverTransitiveDeps` to parse initial modules
**Impact:** Called once per root module
**Cache Status:** ✗ NO CACHE

### 3.3 Compiler.hs Location #2
**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Compiler.hs`
**Line:** 213

```haskell
parseModuleFromPath root srcDirs projectType modName = do
  maybePath <- findModulePath root srcDirs modName
  case maybePath of
    Nothing -> error ("Module not found: " ++ Name.toChars modName)
    Just path -> do
      content <- BS.readFile path
      case Parse.fromByteString projectType content of  -- NO CACHE!
        Left err -> error ("Failed to parse: " ++ path ++ "\nError: " ++ show err)
        Right m -> return m
```

**Context:** Used in `discoverImports` for transitive dependency discovery
**Impact:** Called for each imported module during discovery phase
**Cache Status:** ✗ NO CACHE

### 3.4 Compiler.hs Location #3
**File:** `/home/quinten/fh/canopy/packages/canopy-builder/src/Compiler.hs`
**Line:** 258

```haskell
parseModuleImports :: Parse.ProjectType -> (ModuleName.Raw, FilePath) -> IO (ModuleName.Raw, FilePath, [ModuleName.Raw])
parseModuleImports projectType (modName, path) = do
  content <- BS.readFile path
  case Parse.fromByteString projectType content of  -- NO CACHE!
    Left _err -> return (modName, path, [])
    Right modul -> do
      let imports = [A.toValue (Src._importName imp) | imp <- Src._imports modul]
      return (modName, path, imports)
```

**Context:** Used in `compileModulesInOrder` to extract imports for topological sorting
**Impact:** Called once per module before compilation
**Cache Status:** ✗ NO CACHE

---

## 4. Parse Multiplicity Problem

### Triple (or more) Parsing of Same File

For a typical module `Foo.canopy`, the current system parses it:

1. **Once** in `parseModuleFile` (line 163) - to discover its name and imports
2. **Once** in `parseModuleFromPath` (line 213) - when discovered as a transitive dep
3. **Once** in `parseModuleImports` (line 258) - to build dependency graph
4. **Once** in `Query/Simple.hs` (line 87) - during actual compilation

**Result:** Each file is parsed **4 times** with identical content!

### Evidence from Previous Profiling
From `PERFORMANCE_OPTIMIZATION_RESULTS.md`:
> **Critical Discovery**: `Parse.fromByteString` called **486 times** instead of 162

This confirms the parse multiplicity - files are being parsed 3x more than necessary.

---

## 5. Why Build Succeeded Despite Missing Parse.Cache

The project builds successfully because:

1. The old `/home/quinten/fh/canopy/builder/src/Build.hs` is NOT being compiled
2. Stack/Cabal only compiles what's referenced in package.yaml/cabal files
3. The canopy-terminal package uses the NEW Compiler.hs, not the old Build.hs
4. The reference to `Parse.Cache` in the old Build.hs is simply ignored (file not in build system)

### Build System Structure
```
canopy.cabal (root)
├── packages/canopy-core       (pure functions, parsing, AST)
├── packages/canopy-query      (query system - NO CACHE)
├── packages/canopy-driver     (orchestration)
├── packages/canopy-builder    (compilation - NO CACHE)
└── packages/canopy-terminal   (CLI - uses builder)

/home/quinten/fh/canopy/builder/  ← OLD, NOT COMPILED
```

---

## 6. Runtime Test: No Cache Evidence

### Expected Behavior WITH Cache
```
CACHE MISS: /path/to/Foo.canopy
CACHE HIT: /path/to/Foo.canopy
CACHE HIT: /path/to/Foo.canopy
CACHE HIT: /path/to/Foo.canopy
```

### Actual Behavior WITHOUT Cache
No cache messages appear because:
1. Parse.Cache module doesn't exist
2. No cache lookup/store logic in the actual compilation path
3. Every parse is from scratch via `Parse.fromByteString`

---

## 7. Verification of Claims in Previous Reports

### Claimed Integration Points

Previous reports claimed cache integration at these locations:

| Location | File | Line | Actual Status |
|----------|------|------|---------------|
| crawlFile | Build.hs | ~298 | ✗ File not compiled |
| DepsChange | Build.hs | ~344 | ✗ File not compiled |
| Error reporting | Build.hs | ~362 | ✗ File not compiled |
| fromRepl | Build.hs | ~785 | ✗ File not compiled |
| crawlRoot | Build.hs | ~982 | ✗ File not compiled |
| Details.hs | Canopy/Details.hs | ~747 | ✗ File doesn't exist in packages/ |

**Reality:** ALL claimed integration points are in files that are NOT part of the active build system.

### Claimed Module Structure
Previous reports showed:
```haskell
module Parse.Cache
  ( ParseCache
  , emptyCache
  , cacheLookupOrParse
  , lookupParse
  , insertParse
  ) where
```

**Reality:** This module was never created. The implementation doesn't exist.

---

## 8. Impact Analysis

### Performance Impact
Without parse caching:
- **3-4x redundant parsing** per module
- Each parse includes:
  - Lexical analysis
  - Syntax tree construction
  - All AST allocations
  - String interning

### From Previous Profiling Data
```
Parse.fromByteString: 35.2% of build time
Parse.fromByteString: 28.4% of allocations
```

**With proper caching, we could eliminate 60-75% of this time** by caching results on second/third/fourth parse.

### Estimated Speedup
- Current: 486 parse calls
- With cache: ~162 parse calls (first time only)
- **Potential speedup: 3x in parsing phase**
- **Overall build speedup: 20-30% faster**

---

## 9. Root Cause Analysis

### Why Was This Missed?

1. **Confusion between old and new systems**
   - Old Build.hs was modified but never used
   - New system wasn't checked for cache integration

2. **Successful builds created false confidence**
   - Project builds despite missing Parse.Cache
   - No compile-time errors (module simply not imported)

3. **No runtime verification**
   - No instrumentation to verify cache hits
   - No tests checking cache behavior

4. **Documentation claimed success prematurely**
   - Multiple reports marked integration as "complete"
   - No verification that changes were in active code path

---

## 10. Detailed File Analysis

### Files That SHOULD Have Cache Integration

#### Query/Simple.hs
**Current:**
```haskell
executeQuery :: Query -> IO (Either QueryError QueryResult)
executeQuery query = case query of
  ParseModuleQuery path _ projectType -> do
    content <- BS.readFile path
    case Parse.fromByteString projectType content of
      Left err -> return $ Left $ ParseError path (show err)
      Right modul -> return $ Right $ ParsedModule modul
```

**Should Be:**
```haskell
executeQuery :: MVar ParseCache -> Query -> IO (Either QueryError QueryResult)
executeQuery cacheMVar query = case query of
  ParseModuleQuery path hash projectType -> do
    content <- BS.readFile path
    cache <- takeMVar cacheMVar
    let (result, newCache) = cacheLookupOrParse path projectType content cache
    putMVar cacheMVar newCache
    case result of
      Left err -> return $ Left $ ParseError path (show err)
      Right modul -> return $ Right $ ParsedModule modul
```

#### Compiler.hs (all 3 locations)
Each Parse.fromByteString call should be replaced with cache lookup.

---

## 11. Next Steps Required

### Immediate Actions

1. **Create Parse.Cache module**
   - Location: `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Cache.hs`
   - Export from canopy-core.cabal
   - Implement content-hash based caching

2. **Integrate cache in Query/Simple.hs**
   - Thread ParseCache MVar through query execution
   - Replace Parse.fromByteString with cacheLookupOrParse

3. **Integrate cache in Compiler.hs**
   - Thread cache through all parsing functions
   - Replace 3 Parse.fromByteString calls

4. **Add cache to Driver**
   - Create cache at driver initialization
   - Pass to all query executors

5. **Add instrumentation**
   - Debug logging for cache hits/misses
   - Runtime verification of cache behavior

### Testing Required

1. **Build test with instrumentation**
   - Add trace logging to cache operations
   - Verify cache hits on subsequent parses

2. **Performance benchmarking**
   - Measure before/after parse times
   - Verify reduction in total parse calls

3. **Correctness verification**
   - Ensure cached results match fresh parses
   - Test with file modifications (cache invalidation)

---

## 12. Conclusion

**The parse cache does NOT exist and is NOT being used.**

All previous reports claiming successful integration were incorrect. The modifications were made to old code that is not part of the active build system.

The current system:
- ✗ Has no Parse.Cache module
- ✗ Has no cache integration in Query/Simple.hs
- ✗ Has no cache integration in Compiler.hs
- ✗ Parses each file 3-4 times unnecessarily
- ✗ Wastes 60-75% of parsing time on redundant work

**To achieve the claimed performance benefits, the cache must be:**
1. Actually created (Parse.Cache module)
2. Actually integrated (Query system)
3. Actually used (runtime verification)
4. Actually tested (benchmarks showing improvement)

---

## Appendix A: File Locations Reference

### Active Code (NEEDS CACHE)
- `/home/quinten/fh/canopy/packages/canopy-query/src/Query/Simple.hs` - line 87
- `/home/quinten/fh/canopy/packages/canopy-builder/src/Compiler.hs` - lines 163, 213, 258

### Inactive Code (has ParseCache references but not compiled)
- `/home/quinten/fh/canopy/builder/src/Build.hs` - multiple locations

### Missing Code (needs to be created)
- `/home/quinten/fh/canopy/packages/canopy-core/src/Parse/Cache.hs` - DOES NOT EXIST

---

## Appendix B: Build System Verification Commands

```bash
# Verify Parse.Cache doesn't exist
find /home/quinten/fh/canopy/packages -name "Cache.hs" -path "*/Parse/*"

# Check what's actually being compiled
grep -r "module Build" /home/quinten/fh/canopy/packages/canopy-terminal/src/

# Find all Parse.fromByteString calls in active code
grep -r "Parse.fromByteString" /home/quinten/fh/canopy/packages/canopy-query/
grep -r "Parse.fromByteString" /home/quinten/fh/canopy/packages/canopy-builder/
grep -r "Parse.fromByteString" /home/quinten/fh/canopy/packages/canopy-driver/

# Check exposed modules
grep -A 150 "exposed-modules:" /home/quinten/fh/canopy/packages/canopy-core/canopy-core.cabal | grep "Parse\."
```

---

**Report Status:** COMPLETE
**Severity:** CRITICAL
**Action Required:** IMMEDIATE
