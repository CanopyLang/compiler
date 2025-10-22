# CRITICAL BUG: Code Generation Broken

**Date**: 2025-10-21
**Severity**: 🔴 **CRITICAL** - Compiler produces NO application code
**Status**: ⚠️ **BLOCKING** - Optimizations broke core functionality

---

## Issue Summary

After applying performance optimizations, **Canopy compiler no longer generates application JavaScript code**. It produces only runtime stub functions (78 lines) instead of full application code (should be 16,000+ lines).

### Evidence

**Elm (WORKING):**
```bash
$ elm make src/ContactForm.elm --output=/tmp/elm-contactform.js
Success! ContactForm ───> /tmp/elm-contactform.js

$ ls -lh /tmp/elm-contactform.js
-rw-rw-r-- 1 quinten 604K /tmp/elm-contactform.js  # 16,443 lines ✅
```

**Canopy (BROKEN):**
```bash
$ canopy make src/ContactForm.elm --output=/tmp/contactform-full.js
Success! Compiled 1 module to /tmp/contactform-full.js

$ ls -lh /tmp/contactform-full.js
-rw-rw-r-- 1 quinten 2.8K /tmp/contactform-full.js  # 78 lines ❌
```

### Generated File Content

The entire Canopy output is:
```javascript
(function(scope){'use strict';

// F2-F9 function wrappers (lines 3-50)
// A2-A9 function application (lines 51-74)

console.warn('Compiled in DEV mode...');
_Platform_export({});  // ❌ EMPTY EXPORT
scope['Canopy'] = scope['Elm'];
}(this));
```

**Problem**: `_Platform_export({})` is called with empty object - NO modules exported!

---

## Timeline of Changes

### What We Changed

1. **package.yaml line 107**: Added `-O2` to executable
2. **package.yaml line 110**: Already had `-with-rtsopts=-N`
3. **Canonicalize/Expression.hs**: Removed 4 Debug.Trace calls
   - Lines 576-577 (TopLevel trace)
   - Lines 579-580 (Foreign trace)
   - Lines 591-592 (Qualified lookup trace)
   - Lines 596-597 (Qualified resolution trace)

### When It Broke

Code generation was working BEFORE optimizations:
- Parse cache integration: ✅ Working (showed MISS/HIT traces)
- Parallel compilation: ✅ Working (integrated)
- Performance: ❌ Slow (1.80s) but CODE WAS GENERATED

After optimizations:
- Performance: ✅ Fast (0.62s)
- Code generation: ❌ BROKEN (no output)

---

## Diagnostic Data

### Compilation Reports Success

```bash
$ canopy make src/ContactForm.elm --output=/tmp/test.js
PARSE CACHE HIT: (61 modules)
Success! Compiled 1 module to /tmp/test.js  # ❌ LIES - file is empty
```

### No Artifacts Directory

```bash
$ ls ~/fh/tafkar/components/canopy-stuff/
(no output - directory doesn't exist or is empty)
```

### File Validation

```bash
$ node --check /tmp/contactform-full.js
✅ JavaScript syntax is VALID  # Stub is syntactically valid but useless
```

---

## Root Cause Analysis

### Hypothesis 1: Debug.Trace Removal Broke Something (**MOST LIKELY**)

Removed trace calls from `Canonicalize/Expression.hs`. While trace calls shouldn't affect code generation, **removing them may have accidentally removed critical code**.

**Check:**
- Did we accidentally remove more than just the trace?
- Are there compilation errors we're missing?

### Hypothesis 2: -O2 Flag Changed Behavior

The `-O2` flag enables aggressive optimization. Maybe:
- GHC is optimizing away code generation logic?
- Dead code elimination removing necessary functions?

### Hypothesis 3: Build Artifacts Issue

Maybe:
- Build artifacts are corrupted
- Stack cache is stale
- Wrong version of libraries being linked

---

## Investigation Steps

### Step 1: Revert Debug.Trace Removal

```bash
git diff packages/canopy-core/src/Canonicalize/Expression.hs
git checkout packages/canopy-core/src/Canonicalize/Expression.hs
stack build canopy
canopy make src/ContactForm.elm --output=/tmp/test-reverted.js
ls -lh /tmp/test-reverted.js
```

**Expected**: If traces were the problem, this should fix it.

### Step 2: Remove -O2 Flag

```bash
# Edit package.yaml line 107, remove -O2
stack clean canopy
stack build canopy
canopy make src/ContactForm.elm --output=/tmp/test-no-o2.js
ls -lh /tmp/test-no-o2.js
```

**Expected**: If -O2 was the problem, this should fix it.

### Step 3: Full Clean Rebuild

```bash
stack clean
stack build
canopy make src/ContactForm.elm --output=/tmp/test-clean.js
ls -lh /tmp/test-clean.js
```

### Step 4: Check Build Errors

```bash
stack build canopy 2>&1 | grep -i error
stack build canopy 2>&1 | grep -i warning
```

---

## Impact Assessment

### What's Broken

- ❌ **Code generation**: No application code generated
- ❌ **JavaScript output**: Only runtime stubs
- ❌ **Usability**: Compiler is completely non-functional
- ❌ **Testing**: Cannot test optimizations because nothing works

### What Still Works

- ✅ **Parsing**: Modules are parsed (PARSE CACHE HIT messages appear)
- ✅ **Type checking**: No type errors reported
- ✅ **Compilation "succeeds"**: Returns "Success!" message
- ✅ **Performance**: Fast (0.62s) but produces nothing useful

---

## Immediate Action Required

### Priority 1: Revert Breaking Changes

**REVERT** the Debug.Trace removal from Canonicalize/Expression.hs and test:

```bash
cd /home/quinten/fh/canopy
git diff packages/canopy-core/src/Canonicalize/Expression.hs > /tmp/trace-removal.patch
git checkout packages/canopy-core/src/Canonicalize/Expression.hs
stack clean canopy-core canopy
stack build
cd ~/fh/tafkar/components
canopy make src/ContactForm.elm --output=/tmp/test-after-revert.js
ls -lh /tmp/test-after-revert.js
```

### Priority 2: Bisect to Find Breaking Change

If reverting traces doesn't fix it:
1. Revert -O2 flag
2. Test each change individually
3. Identify exact commit that broke code generation

### Priority 3: Check for Hidden Compilation Errors

```bash
stack build canopy canopy-core --verbose 2>&1 | tee /tmp/build-verbose.log
grep -i "error\|warning\|fail" /tmp/build-verbose.log
```

---

## Test Plan (Once Fixed)

1. ✅ Verify JavaScript output is >500K (not 2.8K)
2. ✅ Verify file contains application code (not just stubs)
3. ✅ Test in browser (HTML page loads without errors)
4. ✅ Verify application functions correctly
5. ✅ Run compiler test suite
6. ✅ Re-measure performance

---

## Conclusion

**Code generation is completely broken after optimizations.**

The compiler:
- Parses files ✅
- Type checks ✅
- Reports "Success" ✅
- But generates NO application code ❌

**Immediate action**: REVERT changes and identify which optimization broke code generation.

**DO NOT** proceed with performance testing until code generation works.

---

**Report Created**: 2025-10-21 06:35 UTC
**Status**: 🔴 CRITICAL BUG - BLOCKING
**Next Step**: Revert Debug.Trace removal and test
