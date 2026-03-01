# Plan 13: FFI Runtime Capability Enforcement

**Priority**: HIGH
**Effort**: Medium (3-4 days)
**Risk**: Medium
**Audit Finding**: `@capability` annotations are parsed from JSDoc but never enforced at runtime; the capability system is documentation theater

---

## Problem

Canopy's FFI capability system currently:
1. Parses `@capability geolocation` from JSDoc comments
2. Stores capability constraints in `FFI/Capability.hs`
3. Does nothing with them

A function marked `@capability geolocation` can be called without any runtime check. Users who rely on the capability annotations for security guarantees are being misled.

---

## Solution

Generate runtime capability checks in the JavaScript output that enforce declared capabilities before FFI functions execute.

---

## Design

### Capability Model

```
Canopy Application
  ├── canopy.json: declares available capabilities
  ├── src/Main.can: imports FFI modules
  └── src/ffi/geolocation.js:
        @capability geolocation
        export function getCurrentPosition() { ... }

Compiled output:
  └── main.js:
        // Capability registry (from canopy.json)
        var _capabilities = {"geolocation": true, "camera": false};

        // Generated guard
        function _ffi_geolocation_getCurrentPosition() {
          _Canopy_checkCapability("geolocation", "getCurrentPosition");
          return _original_getCurrentPosition();
        }
```

### Runtime Check

```javascript
function _Canopy_checkCapability(capability, functionName) {
  if (!_Canopy_capabilities[capability]) {
    throw new Error(
      "Capability '" + capability + "' is required by " + functionName +
      " but not granted in canopy.json. Add it to the 'capabilities' field."
    );
  }
}
```

---

## Implementation

### Step 1: Extend canopy.json Schema

**File: `packages/canopy-core/src/Canopy/Outline.hs`**

Add a `capabilities` field to the project outline:

```haskell
data AppOutline = AppOutline
  { _appSourceDirs :: ![FilePath]
  , _appDeps :: !(Map Pkg.Name Version)
  , _appTestDeps :: !(Map Pkg.Name Version)
  , _appCapabilities :: !(Set Text)  -- NEW
  }
```

Parse from canopy.json:

```json
{
  "type": "application",
  "source-directories": ["src"],
  "capabilities": ["geolocation", "notifications"],
  "dependencies": { ... }
}
```

### Step 2: Collect Capability Requirements During Canonicalization

**File: `packages/canopy-core/src/Canonicalize/Module/FFI.hs`**

When canonicalizing an FFI module, collect all `@capability` annotations:

```haskell
data FFIModuleInfo = FFIModuleInfo
  { _ffiBindings :: ![FFIBinding]
  , _ffiCapabilities :: !(Map Name (Set Capability))  -- NEW: function → required capabilities
  }

-- During canonicalization, extract capabilities per function
extractCapabilities :: JSDocFunction -> Set Capability
extractCapabilities jsDoc =
  Set.fromList (mapMaybe parseCapability (jsDoc ^. jsdocTags))
```

### Step 3: Validate Capabilities Against canopy.json

**File: `packages/canopy-core/src/Canopy/Compiler/Imports.hs`** (or where modules are compiled)

After collecting all required capabilities from FFI modules, check against declared capabilities:

```haskell
-- | Check that all required FFI capabilities are declared in canopy.json.
validateCapabilities
  :: Set Text  -- ^ Declared capabilities from canopy.json
  -> Map Name (Set Capability)  -- ^ Required capabilities from FFI modules
  -> Either [CapabilityError] ()
validateCapabilities declared required =
  let missing = Map.filter (not . all (`Set.member` declared)) required
  in if Map.null missing
     then Right ()
     else Left (map toCapabilityError (Map.toList missing))

data CapabilityError = CapabilityError
  { _ceFunction :: !Name
  , _ceMissing :: !(Set Capability)
  , _ceFile :: !FilePath
  }
```

Error message:

```
-- CAPABILITY ERROR - src/ffi/geolocation.js

The FFI function `getCurrentPosition` requires the `geolocation` capability,
but it is not declared in canopy.json.

Add it to your capabilities list:

    "capabilities": ["geolocation"]
```

### Step 4: Generate Runtime Guards

**File: `packages/canopy-core/src/Generate/JavaScript/FFIRuntime.hs`**

When generating JavaScript for FFI functions with capabilities, wrap them:

```haskell
-- | Generate a capability-guarded FFI binding.
generateGuardedBinding :: Name -> Set Capability -> Builder -> Builder
generateGuardedBinding name caps originalBinding =
  mconcat
    [ "function ", nameToByteString name, "() {\n"
    , concatMap generateCapCheck (Set.toList caps)
    , "  return ", originalBinding, ".apply(this, arguments);\n"
    , "}\n"
    ]

generateCapCheck :: Capability -> Builder
generateCapCheck cap =
  mconcat
    [ "  _Canopy_checkCapability(\""
    , capabilityToByteString cap
    , "\", \""
    , nameToByteString name
    , "\");\n"
    ]
```

### Step 5: Generate Capability Registry

**File: `packages/canopy-core/src/Generate/JavaScript.hs`**

At the top of the generated JavaScript, emit the capability registry:

```haskell
generateCapabilityRegistry :: Set Text -> Builder
generateCapabilityRegistry caps =
  mconcat
    [ "var _Canopy_capabilities = {"
    , BS.intercalate ", " (map (\c -> "\"" <> c <> "\": true") (Set.toList caps))
    , "};\n"
    , "function _Canopy_checkCapability(cap, fn) {\n"
    , "  if (!_Canopy_capabilities[cap]) {\n"
    , "    throw new Error('Capability \\'' + cap + '\\' required by ' + fn + ' but not granted.');\n"
    , "  }\n"
    , "}\n"
    ]
```

### Step 6: Compile-Time Warning for Unused Capabilities

If canopy.json declares capabilities that no FFI function requires:

```
-- WARNING: Unused capability 'camera'

The capability 'camera' is declared in canopy.json but no FFI function
requires it. Consider removing it to minimize your application's
permission surface.
```

---

## Testing

```haskell
testCapabilityEnforcement :: TestTree
testCapabilityEnforcement = testGroup "FFI Capability Enforcement"
  [ testCase "missing capability produces compile error" $ do
      result <- compileWithCapabilities Set.empty [("getLocation", Set.singleton "geolocation")]
      assertBool "should fail" (isLeft result)
  , testCase "declared capability compiles successfully" $ do
      result <- compileWithCapabilities (Set.singleton "geolocation") [("getLocation", Set.singleton "geolocation")]
      assertBool "should succeed" (isRight result)
  , testCase "runtime guard generated" $ do
      js <- generateWithCapabilities (Set.singleton "geolocation") [("getLocation", Set.singleton "geolocation")]
      assertBool "contains check" ("_Canopy_checkCapability" `BS.isInfixOf` js)
  , testCase "unused capability warning" $ do
      (_, warnings) <- compileWithCapabilities (Set.fromList ["geo", "camera"]) [("getLocation", Set.singleton "geo")]
      assertBool "warns about unused" (any isUnusedCapWarning warnings)
  ]
```

---

## Validation

```bash
make build
make test
stack test --ta="--pattern Capability"
```

---

## Success Criteria

- [ ] `canopy.json` accepts a `capabilities` field
- [ ] Missing capabilities produce compile-time errors
- [ ] Runtime guards are generated in JavaScript output
- [ ] Unused capabilities produce compile-time warnings
- [ ] Generated JavaScript throws clear errors on capability violations
- [ ] 15+ tests covering all scenarios
- [ ] `make build` passes, `make test` passes
