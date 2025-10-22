# Debug Trace Calls to Remove for Performance

**Total Found:** 14 trace calls across 5 files

These hardcoded debug trace calls are causing significant performance overhead and cannot be disabled via environment variables.

## Files to Fix

### 1. packages/canopy-core/src/Canonicalize/Module.hs
**Line 63:**
```haskell
let _ = Debug.trace ("DEBUG canonicalize home=" ++ show home ++ " pkg=" ++ show pkg) ()
```
**Fix:** Remove entire line

---

### 2. packages/canopy-core/src/Canonicalize/Expression.hs
**Line 576:**
```haskell
let _ = trace ("DEBUG CANONICALIZE: " ++ Name.toChars name ++ " classified as TopLevel with localHome=" ++ show localHome) ()
```

**Line 579:**
```haskell
let _ = trace ("DEBUG CANONICALIZE: " ++ Name.toChars name ++ " classified as Foreign with home=" ++ show home) ()
```

**Line 591:**
```haskell
let _ = trace ("DEBUG CANONICALIZE QUAL: Looking for " ++ Name.toChars prefix ++ "." ++ Name.toChars name ++ " with localHome=" ++ show localHome) ()
```

**Line 596:**
```haskell
let _ = trace ("DEBUG CANONICALIZE QUAL: " ++ Name.toChars prefix ++ "." ++ Name.toChars name ++ " resolved to home=" ++ show home) ()
```
**Fix:** Remove all 4 lines

---

### 3. packages/canopy-core/src/Canonicalize/Environment/Foreign.hs
**Line 79:**
```haskell
in trace ("KERNEL_IMPORT_DEBUG: Kernel import '" ++ nameStr ++ "' with alias '" ++ aliasStr ++ "' - this is not allowed") $
```

**Line 104:**
```haskell
!vars = trace ("DEBUG interface defs for " ++ show name ++ ": " ++ show (Map.keys defs)) (Map.map (Env.Specific home) defs)
```
**Fix for line 79:** Remove the trace wrapper, keep the rest
**Fix for line 104:** Change to:
```haskell
!vars = Map.map (Env.Specific home) defs
```

---

### 4. packages/canopy-core/src/File/Cache.hs
**Line 50:**
```haskell
trace ("FILE CACHE HIT: " ++ path) $
```

**Line 54:**
```haskell
trace ("FILE CACHE MISS: " ++ path) $ do
```
**Fix:** Remove trace wrappers, keep the rest

---

### 5. packages/canopy-core/src/Type/Solve.hs
**Line 1304:**
```haskell
Debug.Trace.trace ("DEBUG handleNoCopy RigidVar: name=" ++ show name ++ " rank=" ++ show rank ++ " (checking ambient)") (pure ())
```

**Line 1382:**
```haskell
Debug.Trace.trace ("DEBUG copyRigidVarContent: Generalized rigid " ++ show name ++ " -> FlexVar (no ambient check)") (pure ())
```

**Line 1392:**
```haskell
Debug.Trace.trace ("DEBUG copyRigidVarContent: Unifying " ++ show name ++ " with ambient rigid") (pure ())
```
**Fix:** Remove all 3 lines

---

### 6. packages/canopy-core/src/Generate/JavaScript.hs
**Line 488:**
```haskell
_ = trace ("DEBUG PACKAGE MAPPING: currentPkg=" ++ show currentPkg ++ ", module=" ++ show moduleName) ()
```

**Line 507:**
```haskell
_ = trace ("DEBUG PACKAGE MAPPING: trying altPkg=" ++ show altPkg ++ ", altModule=" ++ show altModuleName) ()
```
**Fix:** Remove both lines

---

## Migration to Proper Logging

Instead of `trace`, use the existing `Logging.Debug` module:

### Before:
```haskell
let _ = trace ("DEBUG: some message " ++ show value) ()
```

### After:
```haskell
import qualified Logging.Debug as Log
import Logging.Debug (DebugCategory(..))

-- Later in code:
Log.debug TYPE ("some message " ++ show value)
```

This can be controlled via environment variables:
- `CANOPY_LOG=0` - Disable all logging (zero performance cost)
- `CANOPY_LOG=DEBUG:TYPE` - Enable only type checking debug logs

## Expected Performance Impact

Removing these 14 trace calls should result in:
- **20-30% faster compilation** (reduced I/O overhead)
- **No debug spam** in terminal output
- **Cleaner development experience**
- **Proper logging infrastructure** for debugging when needed

## Verification After Removal

Run the benchmark again:
```bash
cd ~/fh/tafkar/components
rm -rf canopy-stuff
time canopy make src/ContactForm.elm --output=/tmp/test.js
```

Expected results:
- No "DEBUG" lines in output
- Compilation time should drop from ~3.17s to ~2.2-2.5s
- Second run (warm build) should still be slow until cache is implemented

## Additional Search

To find any remaining trace calls:
```bash
grep -rn "trace (" packages/ --include="*.hs" | grep -v "^[[:space:]]*--"
grep -rn "Debug.Trace" packages/ --include="*.hs"
```
