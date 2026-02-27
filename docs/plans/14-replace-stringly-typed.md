# Plan 14 — Replace Stringly-Typed FFI Interfaces

**Priority:** Tier 2 (Type Safety)
**Effort:** 1 day
**Risk:** Medium (changes function signatures across multiple modules)
**Files:** ~8 files

---

## Problem

FFI-related code passes raw `String` and `Text` values where domain-specific newtypes would prevent argument confusion and provide documentation. Key offenders:

1. `Map String String` for JS file path → JS source content (Canonicalize/Module.hs:63)
2. `Map String FFIInfo` for JS file path → FFI info (Generate/JavaScript.hs:102)
3. `[(String, String)]` for (JS function name, Canopy type annotation) (Canonicalize/Module.hs:454)
4. `jsDocFuncName :: !Text` raw JS identifier (Foreign/FFI.hs:134)
5. `PermissionRequired !Text` raw permission name (FFI/Capability.hs:49)

## Implementation

### Step 1: Define newtypes

Create or extend a module (e.g., `FFI/Types.hs` or add to `Foreign/FFI.hs`):

```haskell
-- | Path to a JavaScript source file, relative to project root.
newtype JsSourcePath = JsSourcePath { unJsSourcePath :: FilePath }
  deriving (Eq, Ord, Show)

-- | Raw JavaScript source code content.
newtype JsSource = JsSource { unJsSource :: Text }
  deriving (Eq, Show)

-- | JavaScript function identifier.
newtype JsFunctionName = JsFunctionName { unJsFunctionName :: Text }
  deriving (Eq, Ord, Show)

-- | Canopy type annotation string from @canopy-type JSDoc tag.
newtype CanopyTypeAnnotation = CanopyTypeAnnotation { unCanopyTypeAnnotation :: Text }
  deriving (Eq, Show)

-- | Browser permission name (e.g., "microphone", "geolocation").
newtype PermissionName = PermissionName { unPermissionName :: Text }
  deriving (Eq, Ord, Show)

-- | Browser resource name (e.g., "AudioContext").
newtype ResourceName = ResourceName { unResourceName :: Text }
  deriving (Eq, Ord, Show)

-- | An FFI function binding: the JS name paired with its Canopy type.
data FFIBinding = FFIBinding
  { _bindingName :: !JsFunctionName
  , _bindingType :: !CanopyTypeAnnotation
  } deriving (Eq, Show)
```

### Step 2: Update Map String String → Map JsSourcePath JsSource

In `Canonicalize/Module.hs`:

```haskell
-- Before:
canonicalize :: ... -> Map String String -> ...
-- After:
canonicalize :: ... -> Map JsSourcePath JsSource -> ...
```

Update `loadFFIContent` return type:

```haskell
-- Before:
loadFFIContent :: [Src.ForeignImport] -> IO (Map String String)
-- After:
loadFFIContent :: [Src.ForeignImport] -> IO (Map JsSourcePath JsSource)
```

### Step 3: Update Map String FFIInfo → Map JsSourcePath FFIInfo

In `Generate/JavaScript.hs`:

```haskell
-- Before:
generateFFIContent :: Mode.Mode -> Graph -> Map String FFIInfo -> Builder
-- After:
generateFFIContent :: Mode.Mode -> Graph -> Map JsSourcePath FFIInfo -> Builder
```

### Step 4: Update [(String, String)] → [FFIBinding]

In `Canonicalize/Module.hs`:

```haskell
-- Before:
validateAndAddFunctions :: ... -> [(String, String)] -> ...
-- After:
validateAndAddFunctions :: ... -> [FFIBinding] -> ...
```

### Step 5: Update CapabilityConstraint

In `FFI/Capability.hs`:

```haskell
-- Before:
data CapabilityConstraint
  = PermissionRequired !Text
  | InitializationRequired !Text
  | AvailabilityRequired !Text
-- After:
data CapabilityConstraint
  = PermissionRequired !PermissionName
  | InitializationRequired !ResourceName
  | AvailabilityRequired !Text  -- keep Text for now, define newtype later
```

### Step 6: Update JSDocFunction

In `Foreign/FFI.hs`:

```haskell
-- Before:
data JSDocFunction = JSDocFunction
  { jsDocFuncName :: !Text
  , jsDocFuncParams :: ![(Text, FFIType, Maybe Text)]
-- After:
data JSDocFunction = JSDocFunction
  { jsDocFuncName :: !JsFunctionName
  , jsDocFuncParams :: ![(Text, FFIType, Maybe Text)]  -- param names stay Text for now
```

### Step 7: Fix all compilation errors

The compiler will flag every site where the old `String`/`Text` type was used. Fix each one by wrapping/unwrapping at the boundary. Conversion to/from the newtype should happen at system boundaries (file I/O, serialization), not in internal logic.

## Validation

```bash
make build && make test
```

## Acceptance Criteria

- `Map String String` no longer appears in FFI-related signatures
- `Map String FFIInfo` replaced with `Map JsSourcePath FFIInfo`
- `[(String, String)]` for FFI bindings replaced with `[FFIBinding]`
- `jsDocFuncName` is `JsFunctionName`, not `Text`
- `PermissionRequired` takes `PermissionName`, not `Text`
- `make build && make test` passes
