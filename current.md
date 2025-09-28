# Current Progress: Capability-Based FFI System Implementation

## Overview

We are implementing a comprehensive capability-based FFI (Foreign Function Interface) system for the Canopy compiler (Elm fork). This system provides type-safe Web API access with phantom types that encode browser constraints at compile time.

## Project Status

### ✅ Completed Components

1. **Core Capability Types** - `/home/quinten/fh/canopy/core-packages/capability/src/Capability.can`
   - Rich enum types replacing simple phantom types:
     - `UserActivated` (Click, Keypress, Touch, Drag, Focus, Transient)
     - `Initialized a` (Fresh, Running, Suspended, Interrupted, Restored, Closing)
     - `Permitted a` (Granted, Prompt, Denied, Unknown, Revoked, Restricted)
     - `Available a` (Supported, Prefixed, Polyfilled, Experimental, PartialSupport, LegacySupport)
   - Generic capability checking functions
   - Error types for capability violations

2. **JavaScript FFI Implementation** - `/home/quinten/fh/canopy/core-packages/capability/external/capability.js`
   - User activation detection and consumption
   - Generic API support detection framework
   - Permission checking infrastructure
   - Initialization validation helpers

3. **Audio API Example** - `/home/quinten/fh/canopy/examples/audio-ffi/`
   - Comprehensive audio example using capability types
   - Web Audio API specific implementation building on core framework
   - HTML test page with Playwright validation
   - Demonstrates proper separation between core and API-specific code

4. **Compiler Integration Attempted** - `/home/quinten/fh/canopy/builder/src/Build/Orchestration/Workflow.hs`
   - Modified `makeEnv` function to include `core-packages/capability/src` in source directories
   - Added TODO comments for future removal when canopy/capability becomes real package
   - Applied to both application and package builds

### ✅ RESOLVED: Compilation Issues Fixed

**Status**: **FIXED** - All compilation crashes and deadlocks resolved

#### Root Cause Discovered

The real issue was **NOT** related to kernel module resolution or import handling. Instead, it was **two separate bugs** in the Canopy compiler that were exposed when compiling elm/core 1.0.5:

1. **Vector Bounds Error in Type Solver** (Primary Issue):
   - The type solver initialized pools vector with only 8 elements: `pools <- MVector.replicate 8 []`
   - During type inference, rank values exceeded 8 (specifically rank 26)
   - Multiple functions tried to access `pools[26]` causing "index out of bounds (26,24)" crashes
   - The vector bounds error caused thread crashes, leading to MVar deadlocks

2. **Undefined Function in Import Error Handling** (Secondary Issue):
   - `toImportErrors` function in `Build/Module/Check/Dependencies.hs` was a placeholder returning `undefined`
   - When kernel modules caused import errors, this function was called and crashed
   - This prevented proper error reporting for missing kernel modules

#### Fixes Applied

1. **Fixed Vector Bounds in Type Solver** (`compiler/src/Type/Solve.hs`):
   - Added `ensurePoolSize :: Int -> Pools -> IO Pools` helper function
   - Updated all `MVector.modify pools ... rank` calls to use bounds-safe version
   - Fixed functions: `register`, `registerVariableInOldPool`, `registerOrGeneralizeVariable`, `createFreshCopy`, `introduce`, `srcTypeToVariable`

2. **Implemented Import Error Conversion** (`builder/src/Build/Module/Check/Dependencies.hs`):
   - Replaced `undefined` with proper implementation of `toImportErrors`
   - Added proper error message generation for kernel module import failures
   - Converts import problems into structured `Import.Error` types with regions and context

#### Results

**Before Fix**:
- Vector bounds crashes: `index out of bounds (26,24)`
- MVar deadlocks: `thread blocked indefinitely in an MVar operation`
- Undefined function crashes when kernel modules imported

**After Fix**:
- Clean compilation without crashes
- Proper error messages for kernel module issues:
  ```
  -- MODULE NOT FOUND ---- src/Elm/JsArray.elm
  You are trying to import a `Elm.Kernel.JsArray` module:
  41| import Elm.Kernel.JsArray
  ```
- Graceful dependency failure reporting for elm/core 1.0.5

#### Testing Results

1. ✅ **Individual kernel modules compile successfully** when built alone
2. ✅ **Vector bounds crashes eliminated** - type solver now handles high ranks properly
3. ✅ **MVar deadlocks resolved** - no more thread blocking issues
4. ✅ **Proper error reporting** - kernel import issues now show clear error messages
5. ✅ **Original cms project** shows proper dependency failure message instead of crashing

### 🚧 Why Not in canopy/core Package Yet

The capability system is currently in a temporary `core-packages` directory rather than being a published `canopy/core` package for several strategic reasons:

#### 1. **Package Ecosystem Maturity**
- The Canopy package ecosystem is still in development
- No package registry infrastructure exists yet
- Dependency resolution system needs to support the new capability patterns

#### 2. **API Stability**
- The capability type system is still evolving based on real-world usage
- Rich enum types were recently implemented (replacing simple phantom types)
- FFI interaction patterns are being refined through examples like audio-ffi

#### 3. **Compiler Integration Requirements**
- The capability system needs to be available by default for all Canopy projects
- Similar to how Elm includes `elm/core` automatically
- Current approach allows testing this integration without package system complexity

#### 4. **Bootstrap Problem**
- `canopy/core` would depend on capability system
- But capability system needs to be in `canopy/core` for universal availability
- Temporary `core-packages` allows developing both simultaneously

#### 5. **Build System Dependencies**
- Compiler modifications needed to support automatic inclusion
- Package resolution logic needs updating for capability-aware projects
- Current approach lets us validate compiler changes before package system integration

### 🎯 Next Steps for Kernel Module Support

**Status**: **All crashes resolved** - The Canopy compiler now handles elm/core compilation gracefully without crashes

The remaining work is to implement proper **kernel module delegation** in the Canopy compiler to support the full elm/core package. This is a separate architectural enhancement, not a bug fix.

**Future Kernel Module Work**:
1. Research how the official Elm compiler delegates kernel function calls
2. Implement kernel module interface generation during compilation
3. Add kernel function resolution in the canonicalization phase
4. Test full elm/core package compilation with kernel support

### 🎯 Future Migration Path

When ready to move to `canopy/core`:

1. **Package Infrastructure**:
   - Establish package registry
   - Implement capability-aware dependency resolution
   - Create publishing/versioning workflow

2. **Compiler Updates**:
   - Modify compiler to include `canopy/core` automatically
   - Remove hardcoded `core-packages` path
   - Update build system for package-based approach

3. **API Stabilization**:
   - Finalize capability type hierarchies
   - Establish FFI conventions
   - Create comprehensive documentation

4. **Ecosystem Integration**:
   - Publish initial `canopy/core` with capability system
   - Provide migration guide for existing projects
   - Establish patterns for Web API packages

### 🔍 Technical Architecture

#### Current Directory Structure
```
canopy/
├── core-packages/capability/           # TEMPORARY - will move to canopy/core
│   ├── src/Capability.can             # Core capability types & functions
│   ├── external/capability.js         # JavaScript FFI implementation
│   └── canopy.json                    # Empty (source-only)
├── examples/audio-ffi/                # Example Web Audio API integration
│   ├── src/Main.can                   # Canopy application using capabilities
│   ├── external/audio.js              # Audio-specific FFI functions
│   ├── canopy.json                    # Application config with core-packages path
│   └── test.html                      # Browser validation test page
└── builder/src/Build/Orchestration/
    └── Workflow.hs                    # Modified to include core-packages
```

#### Type System Design
- **Phantom types** encode browser constraints at compile time
- **Rich enums** provide detailed state information vs. simple boolean flags
- **Task-based** error handling for fallible operations
- **Composable** capability checking functions
- **Generic** framework supporting any Web API

#### FFI Interaction Patterns
- **@canopy-type** JSDoc annotations define type signatures
- **JavaScript functions** implement browser-specific logic
- **Canopy functions** provide type-safe wrappers
- **Capability validation** prevents runtime errors

This architecture ensures type safety while maintaining flexibility for diverse Web API patterns.