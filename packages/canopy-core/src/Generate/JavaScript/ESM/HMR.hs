{-# LANGUAGE OverloadedStrings #-}

-- | HMR (Hot Module Replacement) code generation for ESM output.
--
-- Generates HMR support code for TEA (The Elm Architecture) modules.
-- When a @.can@ file changes during development, this enables the Vite
-- plugin to hot-swap the module's @init@\/@update@\/@view@\/@subscriptions@
-- functions without losing the current Model state.
--
-- The generated code includes:
--
--   * @__MODEL_HASH__@ — a structural hash of the Model type, used to
--     detect incompatible model changes that require a full page reload
--   * @__canopy_getModel__()@ — retrieves the current model from the
--     running app instance
--   * @__canopy_hotSwap__(newModule, oldModel)@ — reinitializes the app
--     with updated functions but the old model state
--   * @import.meta.hot.accept()@ — Vite HMR acceptance block
--
-- HMR code is only injected in dev mode. Production builds are unaffected.
--
-- @since 0.20.0
module Generate.JavaScript.ESM.HMR
  ( generateHMRItems,
    hashCanType,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import Data.Bits (xor)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Word (Word32)
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.Mode as Mode

-- | Generate HMR module items for a TEA module in dev mode.
--
-- Returns an empty list for non-TEA modules, production mode, or
-- modules without a @Dynamic@ main.
--
-- @since 0.20.0
generateHMRItems ::
  Mode.Mode ->
  Map ModuleName.Canonical Opt.Main ->
  ModuleName.Canonical ->
  [JS.ModuleItem]
generateHMRItems mode mains home =
  case mode of
    Mode.Prod {} -> []
    Mode.Dev {} ->
      maybe [] (generateForMain home) (Map.lookup home mains)

-- | Generate HMR items for a specific main type.
generateForMain :: ModuleName.Canonical -> Opt.Main -> [JS.ModuleItem]
generateForMain home mainType =
  case mainType of
    Opt.Dynamic modelType _ _ ->
      [ JS.RawJS (modelHashExport (hashCanType modelType)),
        JS.RawJS getModelExport,
        JS.RawJS (hotSwapExport home),
        JS.RawJS hmrAcceptBlock
      ]
    _ -> []

-- MODEL TYPE HASHING

-- | Compute a structural hash of a canonical type.
--
-- Two types with the same structure produce the same hash. When a Model
-- type changes (fields added\/removed, types changed, constructors
-- modified), the hash changes and the HMR runtime triggers a full
-- page reload instead of attempting state preservation.
--
-- @since 0.20.0
hashCanType :: Can.Type -> Word32
hashCanType = go
  where
    go tipe =
      case tipe of
        Can.TLambda a b ->
          combineHash 1 (combineHash (go a) (go b))
        Can.TVar name ->
          combineHash 2 (hashName name)
        Can.TType _home name args ->
          combineHash 3 (combineHash (hashName name) (hashList go args))
        Can.TRecord fields ext ->
          combineHash 4 (combineHash (hashFields fields) (hashExt ext))
        Can.TUnit ->
          5
        Can.TTuple a b mc ->
          combineHash 6 (combineHash (go a) (combineHash (go b) (hashMaybe go mc)))
        Can.TAlias _home name pairs aliasType ->
          combineHash 7 (combineHash (hashName name) (combineHash (hashPairs pairs) (hashAliasType aliasType)))

    hashFields fields =
      Map.foldlWithKey' (\acc k (Can.FieldType _ t) -> combineHash acc (combineHash (hashName k) (go t))) 0 fields

    hashPairs pairs =
      hashList (\(n, t) -> combineHash (hashName n) (go t)) pairs

    hashAliasType (Can.Holey t) = combineHash 10 (go t)
    hashAliasType (Can.Filled t) = combineHash 11 (go t)

    hashExt Nothing = 0
    hashExt (Just name) = hashName name

    hashMaybe _ Nothing = 0
    hashMaybe f (Just x) = combineHash 99 (f x)

    hashList f xs = foldl (\acc x -> combineHash acc (f x)) 0 xs

-- | Hash a Name to a Word32.
hashName :: Name.Name -> Word32
hashName name =
  foldl (\acc c -> acc * 31 + fromIntegral (fromEnum c)) 0 (Name.toChars name)

-- | Combine two hash values using FNV-1a style mixing.
combineHash :: Word32 -> Word32 -> Word32
combineHash h1 h2 =
  (h1 * 16777619) `xor` h2

-- JS CODE GENERATION

-- | Export the model type hash as a constant.
modelHashExport :: Word32 -> Builder
modelHashExport hash =
  "\nexport const __MODEL_HASH__ = \""
    <> BB.word32Hex hash
    <> "\";\n"

-- | Export the getModel function.
--
-- This retrieves the current model from the running app's mutable
-- state. The Canopy runtime stores the model in a closure variable
-- accessible via @_Platform_getModel@.
getModelExport :: Builder
getModelExport =
  "export function __canopy_getModel__() {\
  \ return typeof _Platform_getModel === 'function' ? _Platform_getModel() : undefined;\
  \ }\n"

-- | Export the hotSwap function.
--
-- Reinitializes the TEA app with the new module's functions but
-- preserves the old model state. Calls the platform's hot-swap
-- helper which replaces update\/view\/subscriptions closures.
hotSwapExport :: ModuleName.Canonical -> Builder
hotSwapExport _home =
  "export function __canopy_hotSwap__(newModule, oldModel) {\
  \ if (typeof _Platform_hotSwap === 'function') {\
  \ _Platform_hotSwap(newModule, oldModel);\
  \ }\
  \ }\n"

-- | Generate the import.meta.hot.accept() block for Vite HMR.
--
-- When Vite detects a module change, this block:
-- 1. Gets the old model state
-- 2. Compares model type hashes
-- 3. If hashes match, hot-swaps preserving state
-- 4. If hashes differ, triggers full page reload
hmrAcceptBlock :: Builder
hmrAcceptBlock =
  "\nif (import.meta.hot) {\n\
  \  import.meta.hot.accept((newModule) => {\n\
  \    if (!newModule) return;\n\
  \    const oldModel = __canopy_getModel__();\n\
  \    if (typeof __MODEL_HASH__ !== 'undefined'\n\
  \        && typeof newModule.__MODEL_HASH__ !== 'undefined'\n\
  \        && __MODEL_HASH__ !== newModule.__MODEL_HASH__) {\n\
  \      import.meta.hot.invalidate();\n\
  \      return;\n\
  \    }\n\
  \    if (typeof newModule.__canopy_hotSwap__ === 'function') {\n\
  \      newModule.__canopy_hotSwap__(newModule, oldModel);\n\
  \    }\n\
  \  });\n\
  \}\n"
