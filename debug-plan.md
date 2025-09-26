# Canopy Package Override System - Complete Debug Plan

## 🔍 Root Cause Analysis Summary

### Current State Assessment

**✅ What Works:**
1. **Directory Structure**: `canopy-package-overrides/` system is correctly set up
2. **ZIP Files**: All necessary package ZIP files exist and contain correct content
3. **Configuration Parsing**: `custom-package-repository-config.json` is correctly formatted
4. **Basic Resolution**: Dependencies show "Dependencies ready!" indicating some resolution success
5. **File Structure**: Both directory-based and ZIP-based packages exist in parallel

**❌ Core Problems Identified:**

#### 1. **Version/Directory Mismatch**
- **Issue**: `canopy-package-overrides/canopy/core-1.0.0/` directory exists
- **But**: `custom-package-repository-config.json` references `canopy-core-1.0.5.zip`
- **Result**: Package metadata inconsistency between directory structure and ZIP references

#### 2. **Cache Path Conflicts**
- **Issue**: elm/core goes to `~/.canopy/0.19.1/packages/elm/core/1.0.5/`
- **But**: canopy/core override should go to `~/.canopy/0.19.1/packages/canopy/core/1.0.5/`
- **Result**: Override resolution conflicts with standard package caching

#### 3. **Missing Dependency Declaration**
- **Issue**: `examples/audio-ffi/canopy.json` has `"canopy/core": "1.0.5"`
- **But**: System cannot resolve canopy/core because override mechanism partially broken
- **Result**: "MISSING DEPENDENCY" error despite successful ZIP file location

#### 4. **Incomplete Custom Repository Integration**
- **Issue**: Two config files with different content:
  - `/home/quinten/fh/canopy/examples/audio-ffi/custom-package-repository-config.json` (complete)
  - `~/.canopy/0.19.1/canopy/custom-package-repository-config.json` (simplified)
- **Result**: System may be reading wrong config file or not merging correctly

#### 5. **Package Resolution Order**
- **Issue**: System tries elm registry first, finds elm/core, doesn't check overrides
- **Result**: elm/core is used instead of canopy/core override

---

## 🛠️ Complete Implementation Plan

### Phase 1: Fix Directory/ZIP Version Consistency

**Problem**: Version mismatch between directory names and ZIP file contents

**Root Cause**:
- Directory: `canopy-package-overrides/canopy/core-1.0.0/`
- ZIP name: `canopy-core-1.0.5.zip`
- JSON version in ZIP: `"version": "1.0.5"`

**Solution**:
1. **Option A** (Rename directory): `core-1.0.0/` → `core-1.0.5/`
2. **Option B** (Update ZIP): Create `canopy-core-1.0.0.zip` matching directory
3. **Option C** (Standardize on 1.0.5): Update all references to use 1.0.5 consistently

**Recommended**: Option C - standardize on version 1.0.5
- Rename: `canopy-package-overrides/canopy/core-1.0.0/` → `core-1.0.5/`
- Update all config files to reference 1.0.5 consistently
- Regenerate ZIP file if needed to ensure consistency

### Phase 2: Fix Custom Repository Configuration

**Problem**: Multiple config files with different content

**Current State**:
```bash
# Project-level config (complete)
/home/quinten/fh/canopy/examples/audio-ffi/custom-package-repository-config.json
# 8 single-package-locations defined

# Cache config (minimal)
~/.canopy/0.19.1/canopy/custom-package-repository-config.json
# Only 1 single-package-location defined
```

**Solution**:
1. **Consolidate Configuration**: Use project-level config as source of truth
2. **Update Cache Config**: Copy complete configuration to cache location
3. **Ensure Hash Accuracy**: Replace all "generated" hashes with actual SHA-1 values
4. **Verify File URLs**: Ensure all `file://` URLs point to existing ZIP files

### Phase 3: Fix Cache Path Resolution

**Problem**: Package override extraction conflicts with standard caching

**Current Behavior**:
- elm/core → `~/.canopy/0.19.1/packages/elm/core/1.0.5/`
- canopy/core → Should go to `~/.canopy/0.19.1/packages/canopy/core/1.0.5/`

**Required Changes**:
1. **Verify Cache Structure**: Ensure canopy namespace is used correctly
2. **ZIP Extraction**: Verify ZIP files are extracted to correct cache locations
3. **Hash Validation**: Ensure SHA-1 hashes are checked during extraction
4. **Path Resolution**: Verify dependency resolver uses correct cache paths

### Phase 4: Fix Dependency Resolution Order

**Problem**: System finds elm/core before checking overrides

**Current Flow** (Suspected):
1. Look for elm/core in elm registry → FOUND, use elm/core
2. Never check canopy-package-overrides for elm/core → canopy/core override

**Required Flow**:
1. Check canopy.json dependencies → needs canopy/core
2. Check custom-package-repository-config.json → canopy/core available locally
3. Extract canopy/core ZIP to cache
4. Use canopy/core instead of elm/core

**Implementation**:
1. **Review Deps/Solver.hs**: Ensure single-package-locations checked first
2. **Test Resolution Order**: Verify local packages take precedence
3. **Debug Resolution**: Add logging to show which package sources are checked

### Phase 5: Fix Application-Level Dependencies

**Problem**: audio-ffi example cannot find required packages

**Current Issues**:
- `canopy/core` declared as dependency but not resolved
- `canopy/capability` needed but not declared in canopy.json
- Package override field format may be incorrect

**Required Changes**:
1. **Update canopy.json**: Add all required dependencies including canopy/capability
2. **Verify Override Format**: Ensure package override syntax matches parser expectations
3. **Test Resolution**: Verify all dependencies resolve to correct packages

---

## 🧪 Testing Strategy

### Test 1: Version Consistency Verification
```bash
# Ensure all version references match
grep -r "1.0." examples/audio-ffi/
unzip -p canopy-package-overrides/canopy-core-1.0.5.zip canopy.json | grep version
ls -la canopy-package-overrides/canopy/core-*/
```

### Test 2: Configuration File Validation
```bash
# Verify all ZIP files exist
jq -r '.["single-package-locations"][].url' examples/audio-ffi/custom-package-repository-config.json | xargs -I {} ls -la {}

# Verify all hashes are correct (not "generated")
jq -r '.["single-package-locations"][] | select(.hash == "generated")' examples/audio-ffi/custom-package-repository-config.json
```

### Test 3: Cache Path Validation
```bash
# Check if packages extract to correct locations
ls -la ~/.canopy/0.19.1/packages/canopy/
ls -la ~/.canopy/0.19.1/packages/elm/

# Verify extracted content matches ZIP content
diff -r ~/.canopy/0.19.1/packages/canopy/core/1.0.5/ <(unzip -d /tmp canopy-package-overrides/canopy-core-1.0.5.zip)
```

### Test 4: Dependency Resolution Test
```bash
cd examples/audio-ffi

# Test simplest case
echo 'module Test exposing (main)\nmain = "test"' > src/Test.can
timeout 30 canopy make src/Test.can

# Test core dependency
echo 'module TestCore exposing (main)\nimport List\nmain = List.length []' > src/TestCore.can
timeout 30 canopy make src/TestCore.can

# Test capability dependency
echo 'module TestCap exposing (main)\nimport Capability\nmain = "test"' > src/TestCap.can
timeout 30 canopy make src/TestCap.can
```

### Test 5: End-to-End Compilation Test
```bash
cd examples/audio-ffi

# Test complete audio-ffi compilation
timeout 60 canopy make src/AudioFFI.can

# Verify JavaScript output
ls -la canopy-stuff/
file canopy-stuff/canopy.js
```

---

## 🔧 Implementation Steps

### Step 1: Fix Version Consistency (5 minutes)
1. Rename `canopy-package-overrides/canopy/core-1.0.0/` to `core-1.0.5/`
2. Update any hardcoded version references to use 1.0.5
3. Verify ZIP file contents match directory contents

### Step 2: Generate Correct Hashes (10 minutes)
```bash
# Calculate real SHA-1 hashes for all ZIP files
for zip in canopy-package-overrides/*.zip; do
  echo "$(sha1sum "$zip" | cut -d' ' -f1) $zip"
done

# Update custom-package-repository-config.json with real hashes
sed -i 's/"hash": "generated"/"hash": "ACTUAL_HASH_HERE"/g' examples/audio-ffi/custom-package-repository-config.json
```

### Step 3: Update Cache Configuration (5 minutes)
```bash
# Copy complete config to cache location
cp examples/audio-ffi/custom-package-repository-config.json ~/.canopy/0.19.1/canopy/
```

### Step 4: Add Missing Dependencies (5 minutes)
```bash
# Update audio-ffi canopy.json to include canopy/capability
jq '.dependencies.direct["canopy/capability"] = "1.0.0"' examples/audio-ffi/canopy.json > temp.json
mv temp.json examples/audio-ffi/canopy.json
```

### Step 5: Test and Debug (20 minutes)
1. Run incremental tests (Test 1-4 above)
2. Fix any issues found
3. Run end-to-end test (Test 5)
4. Document any remaining issues

---

## 🎯 Expected Outcomes

### Success Criteria

**After Phase 1-2 (Configuration Fix)**:
- All version numbers consistent across files
- All ZIP file hashes calculated and correct
- Single configuration file used by system

**After Phase 3-4 (Resolution Fix)**:
- `canopy make src/TestCore.can` succeeds (uses canopy/core)
- `canopy make src/TestCap.can` succeeds (uses canopy/capability)
- No "MISSING DEPENDENCY" errors

**After Phase 5 (Complete Fix)**:
- `canopy make src/AudioFFI.can` succeeds
- Generates working `canopy-stuff/canopy.js`
- Browser demo loads and functions correctly

### Failure Points to Watch

1. **ZIP Extraction Failures**: If hashes don't match, extraction will fail
2. **Cache Permission Issues**: If cache directories aren't writable
3. **Package Resolution Order**: If elm registry is still checked first
4. **Module Resolution**: If extracted packages don't have expected modules
5. **JavaScript Generation**: If compilation succeeds but JS generation fails

---

## 🚨 Risk Assessment

### Low Risk Changes
- Renaming directories and updating version numbers
- Calculating and updating hash values
- Copying configuration files

### Medium Risk Changes
- Modifying canopy.json dependency declarations
- Updating cache configurations
- Testing compilation with overrides

### High Risk Changes
- Modifying dependency solver behavior (if needed)
- Changing package extraction logic (if needed)
- Debugging deep compilation issues

---

## 📝 Implementation Notes

### Key Files to Monitor
```bash
# Configuration
examples/audio-ffi/canopy.json                                    # Application dependencies
examples/audio-ffi/custom-package-repository-config.json         # Package overrides config
~/.canopy/0.19.1/canopy/custom-package-repository-config.json    # System config

# Package Sources
canopy-package-overrides/canopy-core-1.0.5.zip                   # Core package ZIP
canopy-package-overrides/canopy/core-1.0.5/                      # Core package directory

# Cache Locations
~/.canopy/0.19.1/packages/canopy/core/1.0.5/                     # Expected extract location
~/.canopy/0.19.1/packages/elm/core/1.0.5/                        # Conflicting elm location

# Build Output
examples/audio-ffi/canopy-stuff/canopy.js                        # Generated JavaScript
```

### Debug Commands
```bash
# Check package resolution
canopy make --verbose src/TestCore.can 2>&1 | grep -E "(Dependency|Package|Cache)"

# Monitor file access during compilation
strace -e trace=openat canopy make src/TestCore.can 2>&1 | grep -E "(canopy|elm)/core"

# Verify extracted package content
find ~/.canopy/0.19.1/packages/ -name "*.can" | head -10
```

### Completion Validation
```bash
# All tests pass
cd examples/audio-ffi
canopy make src/TestCore.can    # Core dependency works
canopy make src/TestCap.can     # Capability dependency works
canopy make src/AudioFFI.can    # Full compilation works

# JavaScript output exists and contains expected content
test -f canopy-stuff/canopy.js && echo "JS generated"
grep -q "audio" canopy-stuff/canopy.js && echo "Audio functions present"
```

This debug plan provides a systematic approach to fixing the canopy package override system by addressing the root causes identified through deep research. The implementation is designed to be incremental with clear success criteria at each phase.