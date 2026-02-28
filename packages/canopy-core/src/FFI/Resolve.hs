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

    -- * Errors
    FFIResolutionError (..),
  )
where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.List as List
import qualified Data.Text as Text
import qualified FFI.Types as FFI
import qualified Canopy.Data.Utf8 as Utf8

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
              (FFI.JsSourcePath (moduleToJsPath modName))
              (FFI.FFIFuncName (Text.unpack funcName)),
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

-- | Check whether a package is in the trusted set for kernel modules.
--
-- Only packages authored by @\"elm\"@ are allowed to use kernel modules.
isTrustedPackage :: Pkg.Name -> Bool
isTrustedPackage pkg =
  Utf8.toChars (Pkg._author pkg) == "elm"
