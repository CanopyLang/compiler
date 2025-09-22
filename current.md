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

### 🔧 Current Technical Challenge

**The core issue**: When I added the core-packages source directory to the compiler, it exposed latent bugs in the build system that prevented compilation.

#### Root Cause Analysis

1. **Latent `undefined` Values**: The build crawl system had placeholder `undefined` values where `Src.Module` (parsed AST) should be passed:
   - Line 209 in `Build/Crawl/Core.hs`: `SChanged local source undefined docsNeed`
   - Line 145 in `Build/Crawl/Processing.hs`: Similar `undefined` usage

2. **Why This Wasn't a Problem Before**:
   - These `undefined` values were never evaluated because the compiler wasn't processing modules that hit these code paths
   - When I added `core-packages/capability/src` to source directories, the compiler started crawling `Capability.can`
   - This triggered the undefined evaluation, causing runtime crashes

3. **MVar Deadlock**: The `undefined` evaluation caused the build thread to crash, leading to an MVar deadlock where other threads waited indefinitely for a result that would never come.

#### Fixes Applied

1. **Updated `processValidatedModule` signature** in `Build/Crawl/Core.hs`:
   - Added `Src.Module` parameter to function signature
   - Updated call site in `parseAndValidateModule` to pass the parsed module
   - Replaced `undefined` with actual `srcModule` in `SChanged` constructor

2. **Enhanced `ValidationConfig` type** in `Build/Crawl/Config.hs`:
   - Added `_validationConfigSrcModule :: !Src.Module` field
   - Updated `createValidationConfig` function signature and implementation
   - Generated lens for new field via `makeLenses`

3. **Fixed `processValidModule`** in `Build/Crawl/Processing.hs`:
   - Updated to use `config ^. validationConfigSrcModule` instead of `undefined`
   - Modified `validateAndProcess` to capture and pass parsed module

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

### 🔄 Current Build Status

**Status**: Compiler rebuild in progress after fixing undefined bugs

**Next Steps**:
1. Complete compiler rebuild with fixes
2. Test audio-ffi example compilation
3. Validate capability system functionality in browser
4. Document integration patterns for other Web APIs

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