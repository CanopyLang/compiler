{-# LANGUAGE OverloadedStrings #-}

-- | Unified FFI resolution layer.
--
-- Provides a single entry point for resolving FFI bindings regardless
-- of whether they use the legacy kernel module mechanism or the newer
-- Canopy FFI system.  This module acts as an adapter that dispatches
-- to the correct underlying system based on the module context.
--
-- == Background
--
-- Canopy inherited two FFI mechanisms from its Elm ancestry:
--
-- 1. **Kernel modules** (@Kernel.*@) -- Used by core library packages
--    (elm/core, elm/browser, etc.) to call JavaScript runtime functions.
--    These are resolved by module name prefix and are restricted to
--    trusted packages.
--
-- 2. **Canopy FFI** (@\@canopy-ffi@ JSDoc annotations) -- The newer,
--    user-facing FFI system that allows any package to declare typed
--    JavaScript bindings through annotated @.js@ files alongside
--    Canopy source modules.
--
-- This module provides 'ResolvedFFI' as a unified representation and
-- 'resolveFFIReference' as a single dispatch point.
--
-- @since 0.19.2
module FFI.Resolve
  ( -- * Resolved FFI Types
    ResolvedFFI (..),
    FFIOrigin (..),

    -- * Resolution
    resolveFFIReference,
    isKernelModule,
    moduleToJsPath,
    moduleToDtsPath,

    -- * npm Resolution
    resolveNpmModule,
    NpmResolution (..),

    -- * Validation
    validateFFIWithDts,

    -- * Errors
    FFIResolutionError (..),
  )
where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.List as List
import Data.Text (Text)
import qualified Data.Text as Text
import FFI.Types (FFIType)
import qualified FFI.Types as FFI
import FFI.TypeValidator (TypeMismatch)
import qualified FFI.TypeValidator as Validator
import Generate.TypeScript.Parser (DtsExport (..))
import qualified Generate.TypeScript.Parser as DtsParser
import Generate.TypeScript.Types (TsType (..))
import qualified System.Directory as Dir
import qualified System.FilePath as FP

-- | A resolved FFI binding with its origin system.
--
-- @since 0.19.2
data ResolvedFFI = ResolvedFFI
  { _resolvedOrigin :: !FFIOrigin,
    _resolvedName :: !Text.Text
  }
  deriving (Show, Eq)

-- | The origin system of an FFI binding.
--
-- @since 0.19.2
data FFIOrigin
  = -- | Legacy kernel module binding (e.g., @Kernel.Utils.eq@).
    KernelOrigin
      !Text.Text
      -- ^ Kernel module name (without @Kernel.@ prefix).
      !Text.Text
      -- ^ Function name within the kernel module.
  | -- | Canopy user FFI binding from a @.js@ file.
    UserFFIOrigin
      !FFI.JsSourcePath
      -- ^ Path to the JavaScript source file.
      !FFI.FFIFuncName
      -- ^ Canopy-side function name.
  deriving (Show, Eq)

-- | Errors during FFI resolution.
--
-- @since 0.19.2
data FFIResolutionError
  = -- | Kernel modules are only allowed in trusted packages.
    KernelNotAllowed !Text.Text !Text.Text
  | -- | No FFI binding found for the given module and name.
    FFINotFound !Text.Text !Text.Text
  deriving (Show, Eq)

-- | Resolve an FFI reference from a module name and function name.
--
-- Dispatches to the kernel module system for @Kernel.*@ prefixed modules
-- in trusted packages, or to the Canopy FFI system for user code.
--
-- @since 0.19.2
resolveFFIReference ::
  Pkg.Name ->
  ModuleName.Raw ->
  Text.Text ->
  Either FFIResolutionError ResolvedFFI
resolveFFIReference pkg modName funcName
  | isKernelModule modName =
      resolveKernelFFI pkg modName funcName
  | otherwise =
      resolveUserFFI modName funcName

-- | Check whether a module name refers to a kernel module.
--
-- Kernel modules have the prefix @\"Kernel.\"@ and are only valid
-- in trusted core packages.
--
-- @since 0.19.2
isKernelModule :: ModuleName.Raw -> Bool
isKernelModule modName =
  List.isPrefixOf "Kernel." (Utf8.toChars modName)

-- INTERNAL

-- | Resolve a kernel module FFI reference.
resolveKernelFFI ::
  Pkg.Name ->
  ModuleName.Raw ->
  Text.Text ->
  Either FFIResolutionError ResolvedFFI
resolveKernelFFI pkg modName funcName
  | isTrustedPackage pkg =
      Right
        ( ResolvedFFI
            { _resolvedOrigin = KernelOrigin kernelModName funcName,
              _resolvedName = funcName
            }
        )
  | otherwise =
      Left (KernelNotAllowed (Text.pack (Utf8.toChars modName)) funcName)
  where
    kernelModName =
      Text.pack (drop (length ("Kernel." :: String)) (Utf8.toChars modName))

-- | Resolve a user FFI reference.
resolveUserFFI ::
  ModuleName.Raw ->
  Text.Text ->
  Either FFIResolutionError ResolvedFFI
resolveUserFFI modName funcName =
  Right
    ( ResolvedFFI
        { _resolvedOrigin =
            UserFFIOrigin
              (FFI.JsSourcePath (Text.pack (moduleToJsPath modName)))
              (FFI.FFIFuncName funcName),
          _resolvedName = funcName
        }
    )

-- | Convert a module name to its expected JavaScript source file path.
moduleToJsPath :: ModuleName.Raw -> String
moduleToJsPath modName =
  map replaceDot (Utf8.toChars modName) ++ ".ffi.js"
  where
    replaceDot '.' = '/'
    replaceDot c = c

-- | Convert a module name to its expected @.d.ts@ companion file path.
--
-- For @Foo.Bar@ returns @\"Foo/Bar.ffi.d.ts\"@. Used to check for
-- companion TypeScript declarations alongside FFI JavaScript files.
--
-- @since 0.20.0
moduleToDtsPath :: ModuleName.Raw -> String
moduleToDtsPath modName =
  map replaceDot (Utf8.toChars modName) ++ ".ffi.d.ts"
  where
    replaceDot '.' = '/'
    replaceDot c = c

-- | Check whether a package is in the trusted set for kernel modules.
--
-- Packages authored by @\"canopy\"@, @\"canopy-explorations\"@, @\"elm\"@,
-- or @\"elm-explorations\"@ are allowed to use kernel modules.
isTrustedPackage :: Pkg.Name -> Bool
isTrustedPackage pkg =
  elem author [Pkg.canopy, Pkg.elm, Pkg.canopyExplorations, Pkg.elmExplorations]
  where
    author = Pkg._author pkg

-- | Validate an FFI binding against its companion @.d.ts@ file, if present.
--
-- Looks for a @.d.ts@ file alongside the FFI JavaScript file (e.g.,
-- @Foo.ffi.js@ -> @Foo.ffi.d.ts@). If found, parses the TypeScript
-- declarations and validates each export against the provided FFI type.
--
-- Returns warnings (not errors) for type mismatches. Returns an empty
-- list if no @.d.ts@ file exists or if all types are compatible.
--
-- @since 0.20.0
validateFFIWithDts ::
  FilePath ->
  ModuleName.Raw ->
  FFIType ->
  IO [Text]
validateFFIWithDts srcRoot modName ffiType = do
  exists <- Dir.doesFileExist dtsPath
  if exists
    then readAndValidateDts dtsPath ffiType
    else pure []
  where
    dtsPath = FP.combine srcRoot (moduleToDtsPath modName)

-- | Read a @.d.ts@ file and validate its exports against an FFI type.
readAndValidateDts :: FilePath -> FFIType -> IO [Text]
readAndValidateDts dtsPath ffiType = do
  content <- readFile dtsPath
  pure (either parseWarning (validateExports ffiType) (DtsParser.parseDtsFile dtsPath content))
  where
    parseWarning err =
      [Text.pack ("Failed to parse " ++ dtsPath ++ ": " ++ err)]

-- | Validate all exports from a parsed @.d.ts@ file against an FFI type.
validateExports :: FFIType -> [DtsExport] -> [Text]
validateExports ffiType =
  concatMap (formatMismatches . validateExport ffiType)

-- | Validate a single export against an FFI type, returning mismatches.
validateExport :: FFIType -> DtsExport -> [TypeMismatch]
validateExport ffiType = \case
  DtsExportFunction _ paramTypes retType ->
    Validator.validateFFIAgainstTs (TsFunction paramTypes retType) ffiType
  DtsExportConst _ tsType ->
    Validator.validateFFIAgainstTs tsType ffiType
  DtsExportInterface _ _ -> []
  DtsExportType _ _ _ -> []

-- | Format type mismatches into human-readable warning messages.
formatMismatches :: [TypeMismatch] -> [Text]
formatMismatches =
  map formatMismatch

-- | Format a single type mismatch into a warning message.
formatMismatch :: TypeMismatch -> Text
formatMismatch mismatch =
  Text.concat
    [ "FFI type mismatch at ",
      Validator._tmPath mismatch,
      ": expected ",
      Validator._tmExpected mismatch,
      " but got ",
      Validator._tmActual mismatch
    ]

-- NPM RESOLUTION

-- | Result of resolving an npm package.
--
-- @since 0.20.1
data NpmResolution = NpmResolution
  { _npmPackageName :: !Text
  , _npmDtsPath :: !FilePath
  , _npmJsEntryPath :: !FilePath
  } deriving (Show, Eq)

-- | Resolve an npm package by name from a project directory.
--
-- Walks up the directory tree looking for @node_modules\/\<package\>@,
-- then reads @package.json@ to find the @types@ or @typings@ entry
-- point. Falls back to @index.d.ts@ if no types field is present.
--
-- @since 0.20.1
resolveNpmModule :: Text -> FilePath -> IO (Maybe NpmResolution)
resolveNpmModule packageName projectDir = do
  let nmPath = FP.combine projectDir ("node_modules" FP.</> Text.unpack packageName)
  exists <- Dir.doesDirectoryExist nmPath
  if exists
    then resolveFromNodeModules packageName nmPath
    else walkUpForNodeModules packageName projectDir

-- | Try to resolve from a found node_modules directory.
resolveFromNodeModules :: Text -> FilePath -> IO (Maybe NpmResolution)
resolveFromNodeModules packageName pkgDir = do
  let pkgJsonPath = FP.combine pkgDir "package.json"
  hasPkgJson <- Dir.doesFileExist pkgJsonPath
  if hasPkgJson
    then resolveFromPackageJson packageName pkgDir pkgJsonPath
    else tryDefaultDts packageName pkgDir

-- | Read package.json and find the types entry point.
resolveFromPackageJson :: Text -> FilePath -> FilePath -> IO (Maybe NpmResolution)
resolveFromPackageJson packageName pkgDir pkgJsonPath = do
  content <- readFile pkgJsonPath
  let typesField = extractTypesField (Text.pack content)
      mainField = extractMainField (Text.pack content)
  case typesField of
    Just dtsRelPath ->
      pure (Just (NpmResolution packageName (FP.combine pkgDir (Text.unpack dtsRelPath)) (resolveMain pkgDir mainField)))
    Nothing -> tryDefaultDts packageName pkgDir

-- | Try to find index.d.ts as a fallback.
tryDefaultDts :: Text -> FilePath -> IO (Maybe NpmResolution)
tryDefaultDts packageName pkgDir = do
  let indexDts = FP.combine pkgDir "index.d.ts"
  exists <- Dir.doesFileExist indexDts
  if exists
    then pure (Just (NpmResolution packageName indexDts (FP.combine pkgDir "index.js")))
    else pure Nothing

-- | Walk up directory tree looking for node_modules.
walkUpForNodeModules :: Text -> FilePath -> IO (Maybe NpmResolution)
walkUpForNodeModules packageName dir = do
  let parentDir = FP.takeDirectory dir
  if parentDir == dir
    then pure Nothing
    else resolveNpmModule packageName parentDir

-- | Extract the "types" or "typings" field from package.json content.
extractTypesField :: Text -> Maybe Text
extractTypesField content =
  extractJsonField "types" content
    `orElse` extractJsonField "typings" content

-- | Extract the "main" field from package.json content.
extractMainField :: Text -> Maybe Text
extractMainField = extractJsonField "main"

-- | Simple JSON field extraction (no full JSON parser needed).
extractJsonField :: Text -> Text -> Maybe Text
extractJsonField field content =
  case Text.breakOn pattern content of
    (_, rest)
      | Text.null rest -> Nothing
      | otherwise -> extractQuotedValue (Text.drop (Text.length pattern) rest)
  where
    pattern = "\"" <> field <> "\": \""

-- | Extract a quoted string value.
extractQuotedValue :: Text -> Maybe Text
extractQuotedValue t =
  case Text.breakOn "\"" t of
    (value, rest)
      | Text.null rest -> Nothing
      | otherwise -> Just value

-- | Resolve the main entry point from package.json.
resolveMain :: FilePath -> Maybe Text -> FilePath
resolveMain pkgDir (Just mainPath) = FP.combine pkgDir (Text.unpack mainPath)
resolveMain pkgDir Nothing = FP.combine pkgDir "index.js"

-- | Choose first non-Nothing value.
orElse :: Maybe a -> Maybe a -> Maybe a
orElse (Just x) _ = Just x
orElse Nothing y = y
