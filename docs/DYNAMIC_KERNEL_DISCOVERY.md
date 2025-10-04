# Dynamic Kernel Discovery Architecture

## Problem

The current `Canopy.Kernel.Registry` hardcodes all kernel modules:

```haskell
kernelRegistry = Map.fromList
  [ mkEntry "Kernel.List" "List operations" CoreOnly
  , mkEntry "Kernel.VirtualDom" "Virtual DOM runtime" (Restricted "Html.*")
  , mkEntryWithPkg "Kernel.Json" "JSON encoding/decoding" CoreOnly Pkg.json
  -- ... hardcoded list
  ]
```

**This is NOT future-proof because:**

1. If `elm/browser` adds `Kernel.Browser`, we must update compiler code
2. If `elm/http` adds `Kernel.Http`, we must update compiler code
3. VirtualDom and Json should not be in the compiler - they're package-specific
4. Third-party packages with kernels (rare but possible) won't work

## Solution: Dynamic Discovery

Instead of hardcoding, **discover kernel modules by scanning package directories**:

```
elm/core/1.0.5/src/Elm/Kernel/
  ├── Basics.js       → Kernel.Basics
  ├── List.js         → Kernel.List
  ├── Utils.js        → Kernel.Utils
  └── ...

elm/json/1.1.3/src/Elm/Kernel/
  └── Json.js         → Kernel.Json

elm/virtual-dom/1.0.3/src/Elm/Kernel/
  └── VirtualDom.js   → Kernel.VirtualDom
```

## Architecture

### 1. Package Extraction (File/Archive.hs)

**When**: During package download and extraction

**What**: After extracting `src/Elm/Kernel/*.js` files, scan the directory

**How**:
```haskell
-- In File/Archive.hs after extraction
discoverKernelModules :: FilePath -> IO [KernelModuleDiscovery]
discoverKernelModules packageDir = do
  let kernelDir = packageDir </> "src" </> "Elm" </> "Kernel"
  exists <- Dir.doesDirectoryExist kernelDir
  if exists
    then do
      files <- Dir.listDirectory kernelDir
      let jsFiles = filter (\f -> ".js" `isSuffixOf` f && not (".server.js" `isSuffixOf` f)) files
          moduleNames = map (\f -> "Kernel." <> takeBaseName f) jsFiles
      pure [KernelModuleDiscovery name | name <- moduleNames]
    else pure []
```

### 2. Kernel Discovery Data Structure

```haskell
-- In Canopy.Kernel.Discovery (NEW MODULE)

data KernelModuleDiscovery = KernelModuleDiscovery
  { _discoveryModuleName :: !Name.Name
    -- ^ Module name (e.g., "Kernel.List", "Kernel.Json")
  , _discoveryPackage :: !Pkg.Name
    -- ^ Source package (e.g., elm/core, elm/json)
  , _discoveryJsPackage :: !Pkg.Name
    -- ^ JavaScript runtime package (usually elm/core)
  , _discoveryHasDollarExport :: !Bool
    -- ^ Whether module has $ entry point (always True for .js kernels)
  }
  deriving (Eq, Show, Generic)

-- Binary instance for serialization to canopy-stuff/
instance Binary KernelModuleDiscovery
```

### 3. Build Artifacts Storage

**Store discovered kernels in canopy-stuff/** alongside interfaces:

```
canopy-stuff/
  ├── 0.19.1/
  │   ├── i.dat           # Existing interfaces
  │   ├── d.dat           # Existing data
  │   └── kernels.dat     # NEW: Discovered kernel modules
```

**Format**: Binary-serialized `Map Pkg.Name [KernelModuleDiscovery]`

```haskell
-- In Builder/Artifacts.hs
type KernelRegistry = Map.Map Pkg.Name [KernelModuleDiscovery]

writeKernelRegistry :: FilePath -> KernelRegistry -> IO ()
writeKernelRegistry stuffDir registry = do
  let kernelsPath = stuffDir </> "0.19.1" </> "kernels.dat"
  BS.writeFile kernelsPath (Binary.encode registry)

readKernelRegistry :: FilePath -> IO (Maybe KernelRegistry)
readKernelRegistry stuffDir = do
  let kernelsPath = stuffDir </> "0.19.1" </> "kernels.dat"
  exists <- Dir.doesFileExist kernelsPath
  if exists
    then Just <$> BS.readFile kernelsPath >>= pure . Binary.decode
    else pure Nothing
```

### 4. Package Build Integration

**When building each package**, discover and store its kernels:

```haskell
-- In Builder/State.hs or similar

buildPackage :: Pkg.Name -> FilePath -> IO BuildResult
buildPackage pkg packageDir = do
  -- Existing build logic...

  -- NEW: Discover kernel modules
  kernels <- discoverKernelModules packageDir

  -- Store in registry
  updateKernelRegistry stuffDir pkg kernels

  -- Continue with compilation...
```

### 5. Code Generation Integration

**During JavaScript generation**, lookup kernels from dynamic registry:

```haskell
-- In Generate/JavaScript.hs

generate :: Mode.Mode -> Opt.GlobalGraph -> Mains -> Map String FFIInfo -> KernelRegistry -> Builder
generate mode globalGraph mains ffiInfos kernelRegistry =
  let graphWithKernels = ensureKernelGlobals globalGraph kernelRegistry
      -- Use discovered kernels, not hardcoded list
```

**Package mapping uses discovery data**:

```haskell
-- In Generate/JavaScript.hs
lookupKernelPackage :: Name.Name -> Pkg.Name -> KernelRegistry -> Maybe Pkg.Name
lookupKernelPackage moduleName currentPkg registry =
  case Map.lookup currentPkg registry of
    Nothing -> Nothing
    Just kernels ->
      case find (\k -> _discoveryModuleName k == moduleName) kernels of
        Just discovery -> Just (_discoveryJsPackage discovery)
        Nothing -> Nothing
```

## Migration Plan

### Phase 1: Add Discovery Infrastructure

1. Create `Canopy.Kernel.Discovery` module
2. Add `discoverKernelModules` to `File/Archive.hs`
3. Add `kernels.dat` storage to build artifacts
4. Implement `KernelRegistry` read/write

### Phase 2: Integrate with Package Build

1. Call `discoverKernelModules` after package extraction
2. Store discoveries in `canopy-stuff/0.19.1/kernels.dat`
3. Read registry during compilation

### Phase 3: Update Code Generation

1. Pass `KernelRegistry` to `Generate.generate`
2. Use dynamic lookup instead of hardcoded registry
3. Update `ensureKernelGlobals` to use discovered modules

### Phase 4: Remove Hardcoded List

1. Keep `Canopy.Kernel.Registry` for:
   - Package mapping rules (canopy/kernel → elm/core logic)
   - Permission checking functions (if needed)
2. Remove hardcoded `kernelRegistry` map
3. Remove VirtualDom, Json, and other package-specific entries

### Phase 5: Testing

1. Test with elm/core only
2. Test with elm/core + elm/json
3. Test with elm/core + elm/json + elm/virtual-dom
4. Test with elm/browser (future package)

## Benefits

✅ **Future-proof**: New packages with kernels work automatically
✅ **No compiler updates**: Adding elm/browser doesn't require compiler changes
✅ **Accurate**: Only kernels that actually exist are registered
✅ **Clean separation**: Compiler doesn't know about package-specific kernels
✅ **Maintainable**: No hardcoded lists to keep in sync

## Package Mapping Rules (Keep in Registry)

The static registry should retain **rules**, not **data**:

```haskell
-- This STAYS (it's a rule, not data)
toJavaScriptPackage :: Name.Name -> Pkg.Name -> Maybe Pkg.Name
toJavaScriptPackage _moduleName currentPkg
  | Pkg._author currentPkg == Pkg.canopy
      && Pkg._project currentPkg == Pkg._project Pkg.kernel =
      Just Pkg.core  -- canopy/kernel → elm/core
  | otherwise = Just currentPkg  -- Package maps to itself

-- This GOES (it's hardcoded data)
-- kernelRegistry :: Map.Map Name.Name KernelModuleInfo
-- kernelRegistry = Map.fromList [...]
```

## Next Steps

1. Implement Phase 1 (discovery infrastructure)
2. Test discovery on elm/core package
3. Integrate with build system (Phase 2)
4. Update code generation (Phase 3)
5. Remove hardcoded entries (Phase 4)
