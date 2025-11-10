# Canopy Compiler Runtime & Type-Safe FFI Modernization Plan

## 🎯 Executive Summary

This plan outlines a comprehensive redesign of Canopy's runtime architecture, moving from unsafe external dependencies to a modern, type-safe system comprising:

1. **Built-in Runtime**: Core elm/core functionality embedded in the compiler
2. **Type-Safe FFI**: Revolutionary foreign function interface with compile-time verification
3. **Security Model**: Sandboxed execution with capability-based permissions
4. **Migration Strategy**: Smooth transition path for existing ecosystem

**Goal**: Transform Canopy from a "hope it works" system to a production-ready, secure, type-safe compiler that rivals Rust and Go in reliability.

---

## 🏗️ Part 1: Embed elm/core in Compiler

### Phase 1: Core Runtime Integration (3-4 months)

#### 1.1 Essential Primitives (Built into Compiler)
```haskell
-- Type System Primitives (Zero Dependencies)
data RuntimePrimitive =
  | TupleConstructor Int        -- _Utils_Tuple2, _Utils_Tuple3
  | EqualityOperator           -- _Utils_eq (type-safe)
  | ComparisonOperator         -- _Utils_cmp (type-safe)
  | ArithmeticOp BinaryOp      -- add, sub, mul, div
  | ListConstructor            -- _List_Cons, _List_Nil
  | StringOperation StringOp   -- concat, slice, etc.
  | PlatformExport            -- _Platform_export (secure)

-- Generated as inline JavaScript, not function calls
compileAdd :: Expr -> Expr -> JSExpr
compileAdd left right = JSBinary JSAdd (exprToJS left) (exprToJS right)
-- Result: Direct `x + y` instead of `_Basics_add(x, y)`
```

#### 1.2 Compiler-Generated Runtime
```javascript
// OLD (elm/core dependency):
var result = _Basics_add(x, y);  // External function call

// NEW (compiler-generated):
var result = x + y;              // Direct JavaScript operation
```

#### 1.3 Security Model
```haskell
-- Capability-based runtime permissions
data RuntimeCapability =
  | SafeArithmetic    -- +, -, *, / operations
  | SafeComparison    -- ==, <, > operations
  | SafeDataAccess    -- Record/list access
  | ConsoleOutput     -- console.log (dev mode only)
  | NoNetworkAccess   -- Explicitly forbidden
  | NoDOMAccess       -- Explicitly forbidden (use FFI)
  | NoFileSystemAccess -- Explicitly forbidden

-- Runtime functions ONLY have access to their declared capabilities
```

#### 1.4 Implementation Strategy
```haskell
-- In compiler/src/Generate/Runtime.hs (NEW)
generateRuntimePrimitive :: RuntimePrimitive -> Mode -> JSExpr
generateRuntimePrimitive TupleConstructor 2 mode =
  -- Generate: { $: '#2', a: a, b: b }
  JSObject [("$", JSString "#2"), ("a", JSIdent "a"), ("b", JSIdent "b")]

generateRuntimePrimitive EqualityOperator mode =
  -- Generate type-safe equality with compile-time verification
  generateTypeSafeEquality mode

-- NO external JavaScript dependencies for core operations
```

---

## 🌟 Part 2: Pragmatic Type-Safe FFI System

### 2.1 Lessons from Other Languages

**Gleam's Approach:**
```gleam
@external(javascript, "./my_module.mjs", "doThing")
pub fn do_thing(x: Int) -> String
```

**Canopy's Refined Approach (Explicit and Safe):**
```elm
-- Method 1: Explicit Foreign Declarations (Primary)
foreign import javascript "./dom.js" as DOM

-- Explicit type signatures with runtime validation
createElement : String -> Result DOMError DOMElement
createElement = DOM.createElement

-- Method 2: WebAssembly Integration (Future)
foreign import wasm "./crypto.wasm" as Crypto
hash : String -> Bytes
hash = Crypto.sha256

-- Method 3: Gradual TypeScript Integration (When Mature)
foreign import typescript "./api.d.ts" as API
-- Only for well-typed, mature TypeScript libraries
```

### 2.2 Controlled JSDoc Type Integration (Primary Approach)

#### 2.2.1 JavaScript Side (JSDoc + Runtime Validation)
```javascript
// external/dom.js
// We control the JSDoc annotations to match our Canopy functions exactly

/**
 * Creates a DOM element with the specified tag name
 * @canopy-type String -> Result DOMError DOMElement
 * @param {string} tagName - HTML tag name (must be valid HTML tag)
 * @returns {Element} The created DOM element
 * @throws {TypeError} When tagName is not a string
 * @throws {DOMException} When tagName is invalid HTML
 */
export function createElement(tagName) {
    // Runtime validation matches JSDoc contract
    if (typeof tagName !== 'string') {
        throw new TypeError('createElement: tagName must be a string');
    }
    try {
        return document.createElement(tagName);
    } catch (e) {
        throw new DOMException(`Invalid tag name: ${tagName}`);
    }
}

/**
 * Finds the first element matching the CSS selector
 * @canopy-type String -> Maybe DOMElement
 * @param {string} selector - CSS selector string
 * @returns {Element|null} The found element or null
 * @throws {TypeError} When selector is not a string
 * @throws {DOMException} When selector is invalid CSS
 */
export function querySelector(selector) {
    if (typeof selector !== 'string') {
        throw new TypeError('querySelector: selector must be a string');
    }
    try {
        return document.querySelector(selector);
    } catch (e) {
        throw new DOMException(`Invalid CSS selector: ${selector}`);
    }
}

/**
 * Fetch with timeout support
 * @canopy-type String -> Int -> Task HttpError Response
 * @param {string} url - The URL to fetch
 * @param {number} timeoutMs - Timeout in milliseconds
 * @returns {Promise<Response>} The fetch response
 * @throws {TypeError} When parameters have wrong types
 * @throws {TimeoutError} When request times out
 * @throws {NetworkError} When network fails
 */
export async function fetchWithTimeout(url, timeoutMs) {
    if (typeof url !== 'string') {
        throw new TypeError('fetchWithTimeout: url must be a string');
    }
    if (typeof timeoutMs !== 'number') {
        throw new TypeError('fetchWithTimeout: timeoutMs must be a number');
    }

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

    try {
        const response = await fetch(url, { signal: controller.signal });
        clearTimeout(timeoutId);
        return response;
    } catch (e) {
        clearTimeout(timeoutId);
        if (e.name === 'AbortError') {
            throw new TimeoutError(`Request timed out after ${timeoutMs}ms`);
        }
        throw new NetworkError(`Network error: ${e.message}`);
    }
}
```

#### 2.2.2 Canopy Side (Auto-Generated from JSDoc)
```elm
-- src/External/DOM.can
foreign import javascript "./external/dom.js" exposing (..)

-- Compiler automatically generates these types from @canopy-type annotations:
-- createElement : String -> Result DOMError DOMElement
-- querySelector : String -> Maybe DOMElement
-- fetchWithTimeout : String -> Int -> Task HttpError Response

-- Generated wrapper functions handle error conversion:
createDivElement : Result DOMError DOMElement
createDivElement = createElement "div"

findAppElement : Maybe DOMElement
findAppElement = querySelector "#app"

loadUserData : String -> Task HttpError Response
loadUserData userId = fetchWithTimeout ("/api/users/" ++ userId) 5000

-- Usage is completely type-safe!
main =
    case createDivElement of
        Ok element ->
            case findAppElement of
                Just container ->
                    div [] [ text "Both operations succeeded!" ]
                Nothing ->
                    div [] [ text "Container not found" ]
        Err (DOMError.InvalidTag msg) ->
            div [] [ text ("DOM Error: " ++ msg) ]
```

#### 2.2.3 Compiler JSDoc Processing
```haskell
-- In compiler/src/Foreign/JSDoc.hs (NEW)
data JSDocAnnotation = JSDocAnnotation
  { jsDocCanopyType :: !Text        -- @canopy-type String -> Result Error Value
  , jsDocParams :: ![JSDocParam]    -- @param annotations
  , jsDocReturns :: !Text           -- @returns annotation
  , jsDocThrows :: ![Text]          -- @throws annotations
  }

parseJSDocFromFile :: FilePath -> IO [JSDocFunction]
parseJSDocFromFile jsFile = do
  content <- Text.readFile jsFile
  return $ extractJSDocFunctions content

-- Parse @canopy-type annotation into Canopy type
parseCanopyType :: Text -> Either ParseError Type
parseCanopyType "String -> Result DOMError DOMElement" =
  Right $ TFunc TString (TApp (TConstructor "Result") [TConstructor "DOMError", TConstructor "DOMElement"])

-- Generate Canopy wrapper function
generateFFIWrapper :: JSDocFunction -> CanopyFunction
generateFFIWrapper jsFunc = CanopyFunction
  { canopyName = jsFunc.name
  , canopyType = parseCanopyType jsFunc.canopyType
  , canopyImplementation = generateErrorHandlingWrapper jsFunc
  }

-- CONTROLLED APPROACH: We write both JSDoc and Canopy sides!
```

### 2.3 Advanced FFI Features

#### 2.3.1 Static Security Analysis (Compile-Time Only)
```elm
-- Security through static analysis, not runtime overhead
module MyApp exposing (main)

-- Static analysis detects potentially dangerous patterns
foreign import javascript "./api.js" as API

-- Compiler warnings for risky operations:
-- ⚠️  Warning: Function 'eval' detected in ./api.js
-- ⚠️  Warning: Global access 'window' detected in ./api.js
-- ⚠️  Warning: Network request without timeout detected

sendRequest : String -> Task HttpError Response
sendRequest = API.sendRequest
```

#### 2.3.2 Explicit Error Handling Patterns
```javascript
// external/api.js
// Clear error handling without magic annotations

export async function fetchData(url) {
    if (typeof url !== 'string') {
        throw new TypeError('fetchData: url must be a string');
    }

    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        return response;
    } catch (error) {
        // Normalize error types
        if (error instanceof TypeError) {
            throw new Error(`Network error: ${error.message}`);
        }
        throw error;
    }
}
```

```elm
-- Explicit error handling in Canopy
fetchData : String -> Task HttpError Response
fetchData url =
    API.fetchData url
    |> Task.mapError parseHttpError

parseHttpError : String -> HttpError
parseHttpError message =
    if String.startsWith "HTTP " message then
        HttpError.BadStatus (extractStatusCode message)
    else if String.contains "Network" message then
        HttpError.NetworkError
    else
        HttpError.BadUrl message
```

#### 2.3.3 WebAssembly Integration
```elm
-- Future: Direct WebAssembly imports
foreign import wasm "./crypto.wasm" as Crypto

hash : String -> Bytes
hash = Crypto.sha256  -- Direct WASM call, maximum performance
```

---

## 🚀 Part 3: Implementation Strategies

### 3.1 Strategy A: JSDoc + Runtime Validation (Recommended)

**Advantages:**
- ✅ Leverage existing JavaScript ecosystem
- ✅ Compile-time AND runtime type checking
- ✅ Gradual adoption possible
- ✅ Excellent error messages
- ✅ IDE integration potential

**Implementation:**
```haskell
-- 1. Parse JSDoc comments from JavaScript files
parseJSDocTypes :: FilePath -> IO [JSDocFunction]

-- 2. Generate Canopy type signatures
jsDocToCanopyType :: JSDocType -> CanopyType

-- 3. Generate runtime type validation
generateRuntimeChecks :: JSDocFunction -> JSExpr

-- 4. Compile-time verification
verifyFFIUsage :: CanopyExpr -> JSDocFunction -> Either TypeError ()
```

### 3.2 Strategy B: TypeScript Declaration Integration

**For Maximum Ecosystem Compatibility:**
```elm
-- Import existing TypeScript definitions
foreign import typescript "@types/node/fs.d.ts" as FS
foreign import typescript "@types/react/index.d.ts" as React

-- Automatic conversion of TypeScript types to Canopy types
readFile : String -> Task FileError String
readFile = FS.readFile

-- Access to ENTIRE TypeScript ecosystem!
```

**Implementation:**
```haskell
-- compiler/src/Foreign/TypeScript.hs
parseTypeScriptDeclaration :: FilePath -> IO [TSDeclaration]
tsTypeToCanopyType :: TSType -> CanopyType
generateFFIBindings :: [TSDeclaration] -> [CanopyBinding]
```

### 3.3 Strategy C: Rust-Style Extern Blocks

**For Maximum Control:**
```elm
-- Explicit foreign declarations with full type control
foreign block "DOM" "./dom.js" exposing
    createElement : String -> DOMElement
    querySelector : String -> Maybe DOMElement
    addEventListener : DOMElement -> String -> (DOMEvent -> msg) -> Cmd msg

-- Compiler verifies JavaScript implementations match signatures
```

---

## 🛡️ Part 4: Security & Reliability Model

### 4.1 Capability System
```elm
-- Each module declares required capabilities
module WebApp exposing (main)

capabilities
    [ DOM_ACCESS      -- Can manipulate DOM
    , HTTP_CLIENT     -- Can make HTTP requests
    , LOCAL_STORAGE   -- Can access localStorage
    -- NOT: FILE_SYSTEM, NATIVE_CODE, EVAL
    ]

-- Capabilities are:
-- 1. Explicitly declared (no hidden dependencies)
-- 2. Compile-time verified (no runtime surprises)
-- 3. Minimal by default (principle of least privilege)
-- 4. Auditable (security review possible)
```

### 4.2 Runtime Sandboxing
```javascript
// Generated runtime wrapper (automatic)
const secureFFI = {
    // Only allowed capabilities are exposed
    createElement: window.document ? dom.createElement : throwCapabilityError,
    fetch: navigator.onLine ? api.fetch : throwCapabilityError,
    // File system access: NEVER exposed to web targets
    readFile: undefined, // Compile-time error if used
};

// No access to global scope, eval, or dangerous APIs
```

### 4.3 Type Safety Guarantees
```haskell
-- Compile-time guarantees:
data FFISafety =
  | TypesVerified        -- Input/output types match exactly
  | ErrorsExplicit       -- All error cases are handled
  | CapabilitiesMinimal  -- Only required capabilities granted
  | NoArbitraryJS        -- No eval, Function(), or dynamic code
  | SandboxedExecution   -- No access to global scope
  | MemorySafe          -- No buffer overflows or memory corruption

-- Runtime guarantees:
-- 1. Type assertions on all FFI boundaries
-- 2. Capability enforcement
-- 3. Error isolation (FFI errors don't crash runtime)
-- 4. Resource limits (prevent DoS attacks)
```

---

## 📋 Part 5: Implementation Timeline

### Phase 1: Foundation (Months 1-4)
```
Week 1-2:   Architecture design and RFC
Week 3-6:   Core runtime primitives implementation
Week 7-10:  Basic FFI infrastructure (JSDoc parsing)
Week 11-16: Security model and capability system
```

### Phase 2: FFI System (Months 5-8)
```
Week 17-20: JSDoc type conversion system
Week 21-24: Runtime type validation generation
Week 25-28: TypeScript declaration support
Week 29-32: Comprehensive testing and validation
```

### Phase 3: Ecosystem Integration (Months 9-12)
```
Week 33-36: Migration tools for existing packages
Week 37-40: IDE integration and tooling
Week 41-44: Documentation and tutorials
Week 45-48: Community feedback and refinement
```

### Phase 4: Advanced Features (Months 13+)
```
- WebAssembly integration
- Advanced security features
- Performance optimizations
- Browser/Node.js specific optimizations
```

---

## 🔄 Part 6: Automatic Migration Strategy (Zero Breaking Changes)

### 6.1 Smart Runtime Detection (Revolutionary Backwards Compatibility)

**The Key Insight**: Automatically detect project type and choose appropriate runtime strategy.

#### 6.1.1 Elm Project Detection
```bash
# Canopy automatically detects Elm projects
canopy make src/Main.elm

# Compiler checks:
# 1. Does elm.json exist?
# 2. Does canopy.json contain elm/core dependency?
# 3. Are there kernel imports in source files?

# IF YES: Use legacy elm/core kernel approach (100% compatibility)
# IF NO:  Use new built-in runtime (automatic optimization)
```

#### 6.1.2 Implementation in Compiler
```haskell
-- In compiler/src/Build/ProjectType.hs (NEW)
data ProjectType =
  | ElmProject        -- Has elm/core dependency, use kernel code
  | CanopyProject     -- Pure Canopy, use built-in runtime
  | HybridProject     -- Mixed, user choice required

detectProjectType :: FilePath -> IO ProjectType
detectProjectType projectRoot = do
  elmJson <- doesFileExist (projectRoot </> "elm.json")
  canopyJson <- doesFileExist (projectRoot </> "canopy.json")

  case (elmJson, canopyJson) of
    (True, False) -> checkElmDependencies projectRoot
    (False, True) -> checkCanopyDependencies projectRoot
    (True, True)  -> return HybridProject  -- User must choose
    (False, False) -> return CanopyProject -- Default to new runtime

checkElmDependencies :: FilePath -> IO ProjectType
checkElmDependencies root = do
  deps <- parseElmJson (root </> "elm.json")
  return $ if "elm/core" `elem` deps
           then ElmProject
           else CanopyProject

-- AUTOMATIC: No user intervention required!
```

#### 6.1.3 Runtime Selection Logic
```haskell
-- In compiler/src/Generate.hs
generateWithProjectType :: ProjectType -> Artifacts -> Builder
generateWithProjectType projectType artifacts = case projectType of

  ElmProject -> do
    -- Use legacy elm/core kernel approach (existing code path)
    -- Include external elm/core dependencies
    -- Support all existing kernel imports
    generateLegacyElmRuntime artifacts

  CanopyProject -> do
    -- Use new built-in runtime (revolutionary approach)
    -- Automatically include core primitives
    -- Enable new FFI system
    generateBuiltInRuntime artifacts

  HybridProject -> do
    -- Provide clear migration guidance
    -- Allow user to choose approach
    promptUserForRuntimeChoice artifacts
```

### 6.2 Zero-Friction Elm Compatibility

#### 6.2.1 Existing Elm Projects (100% Compatible)
```bash
# Existing Elm project
elm make src/Main.elm --output=main.js

# Switch to Canopy (ZERO code changes required)
canopy make src/Main.elm --output=main.js
# ✅ Identical output, identical behavior
# ✅ All elm/core kernel functions work exactly the same
# ✅ All existing packages work without modification
```

#### 6.2.2 New Canopy Projects (Automatic Optimization)
```bash
# New Canopy project (no elm.json)
canopy init my-app
canopy make src/Main.can --output=main.js

# ✅ Automatically uses built-in runtime
# ✅ No elm/core dependency needed
# ✅ Type-safe FFI available immediately
# ✅ Security model enabled by default
# ✅ Performance optimizations active
```

### 6.3 Gradual Migration Path

#### 6.3.1 Migration by Dependency Removal
```json
// elm.json (Elm project - uses legacy runtime)
{
  "dependencies": {
    "direct": {
      "elm/core": "1.0.5",    // ← Remove this line
      "elm/html": "1.0.0"
    }
  }
}

// canopy.json (Canopy project - uses built-in runtime)
{
  "dependencies": {
    "direct": {
      "elm/html": "1.0.0"     // ← elm/core automatically provided
    }
  }
}
```

#### 6.3.2 Migration Command
```bash
# Automatic migration tool
canopy migrate-to-builtin ./
# ✅ Removes elm/core from dependencies
# ✅ Updates import statements if needed
# ✅ Validates compatibility
# ✅ Shows performance improvements

# Migration is REVERSIBLE
canopy migrate-to-legacy ./
# ✅ Adds elm/core back to dependencies
# ✅ Ensures 100% backwards compatibility
```

### 6.2 Migration Tools
```bash
# Automatic migration tool
canopy migrate-ffi ./src/MyPackage.elm
# Converts old kernel code to new FFI syntax

# FFI validation tool
canopy validate-ffi ./external/api.js
# Verifies JavaScript matches JSDoc type annotations

# Capability analyzer
canopy analyze-capabilities ./src/
# Shows what capabilities are actually used vs declared
```

---

## 🎯 Part 7: Revolutionary Advantages

### 7.1 vs Current Elm Approach
```
Current Elm:     Unchecked kernel code, "hope it works"
Canopy:         Compile-time verified, runtime-safe FFI

Current Elm:     Limited foreign function capabilities
Canopy:         Full JavaScript/WASM ecosystem access

Current Elm:     No security model
Canopy:         Capability-based security with sandboxing

Current Elm:     Difficult to debug FFI issues
Canopy:         Rich error messages and type checking
```

### 7.2 vs Other Languages
```
Rust:           Unsafe blocks, manual memory management
Canopy:         Type-safe FFI with automatic memory management

PureScript:     Complex FFI syntax, limited tooling
Canopy:         Simple syntax with excellent tooling

ReScript:       No type safety at FFI boundaries
Canopy:         Full type safety everywhere

JavaScript:     No type safety anywhere
Canopy:         Type safety with JavaScript ecosystem access
```

### 7.3 Unique Innovations
```
1. JSDoc type integration (first of its kind)
2. Capability-based security for web languages
3. Compile-time FFI verification with runtime safety
4. Seamless TypeScript ecosystem integration
5. WebAssembly-first foreign function design
```

---

## ⚡ Part 8: Performance Benefits

### 8.1 Built-in Runtime
```javascript
// OLD: Function call overhead
var result = _Basics_add(_Basics_mul(x, 2), y);

// NEW: Direct JavaScript operations
var result = (x * 2) + y;

// Performance improvement: 2-5x faster for arithmetic
```

### 8.2 Optimized FFI
```javascript
// OLD: Generic runtime wrapper
function callFFI(funcName, args) {
    return window[funcName].apply(null, args);
}

// NEW: Direct function calls with inline type checks
function createElement_checked(tagName) {
    if (typeof tagName !== 'string') throw new TypeError('Expected string');
    return createElement(tagName);  // Direct call
}

// Performance improvement: 10-20x faster FFI calls
```

### 8.3 Dead Code Elimination
```haskell
-- Compiler knows exactly what's used
-- Only includes necessary runtime functions
-- Tree-shaking at the primitive level
-- Smaller bundle sizes: 50-80% reduction possible
```

---

## 🎉 Conclusion: The Future of Type-Safe Compilation

This plan transforms Canopy from an Elm clone into a **revolutionary compiler** that:

1. **Eliminates "hope it works" programming** with compile-time verified FFI
2. **Provides security guarantees** through capability-based permissions
3. **Delivers performance benefits** with built-in optimized runtime
4. **Enables JavaScript ecosystem access** while maintaining type safety
5. **Sets new standards** for what a modern compiler should provide

**This isn't just an improvement - it's a paradigm shift that makes Canopy competitive with Rust, Go, and other modern languages while retaining the simplicity and safety of functional programming.**

The combination of built-in runtime + type-safe FFI creates a **unique value proposition** that no other language currently offers:

> **"All the safety of Haskell, all the ecosystem of JavaScript, with the performance of native compilation."**

This is the future of web development, and Canopy can lead the way.