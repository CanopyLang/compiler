{-# LANGUAGE OverloadedStrings #-}

-- | TypeScript @.d.ts@ declaration file generation.
--
-- Generates TypeScript declaration files from Canopy module interfaces.
-- Each compiled Canopy module produces a @.d.ts@ file alongside its @.js@
-- file, enabling TypeScript consumers to import Canopy modules with full
-- type safety.
--
-- = Type Mapping
--
-- @
-- Canopy          TypeScript
-- String          string
-- Int, Float      number
-- Bool            boolean
-- ()              void
-- List a          ReadonlyArray\<A\>
-- Maybe a         { $: \'Just\'; a: A } | { $: \'Nothing\' }
-- Result e a      { $: \'Ok\'; a: A } | { $: \'Err\'; a: E }
-- { x: Int }      { readonly x: number }
-- a -> b -> c     (p0: A, p1: B) => C
-- @
--
-- @since 0.20.0
module Generate.TypeScript
  ( generateDts,
    generateFromInterface,
  )
where

import Canopy.Data.Name (Name)
import qualified Canopy.Interface as Iface
import qualified AST.Canonical as Can
import Data.ByteString.Builder (Builder)
import qualified Data.Map.Strict as Map
import qualified Generate.TypeScript.Convert as Convert
import qualified Generate.TypeScript.Render as Render
import Generate.TypeScript.Types (DtsDecl (..))

-- | Generate a @.d.ts@ file from an interface.
--
-- Produces TypeScript declarations for all public values, types, and
-- aliases exported by the module.
--
-- @since 0.20.0
generateDts :: Iface.Interface -> Builder
generateDts iface =
  Render.renderDecls (generateFromInterface iface)


-- | Generate a list of TypeScript declarations from an interface.
generateFromInterface :: Iface.Interface -> [DtsDecl]
generateFromInterface iface =
  valueDecls ++ unionDecls ++ aliasDecls
  where
    valueDecls = map (uncurry Convert.convertValue) (Map.toAscList (Iface._values iface))
    unionDecls = concatMap (uncurry convertUnionExport) (Map.toAscList (Iface._unions iface))
    aliasDecls = concatMap (uncurry convertAliasExport) (Map.toAscList (Iface._aliases iface))


-- | Convert a union export to declarations (skip private unions).
convertUnionExport :: Name -> Iface.Union -> [DtsDecl]
convertUnionExport name (Iface.OpenUnion union) = [Convert.convertUnion name union]
convertUnionExport name (Iface.ClosedUnion union) = [Convert.convertUnion name union]
convertUnionExport _ (Iface.PrivateUnion _) = []


-- | Convert an alias export to declarations (branded for opaque, skip private).
convertAliasExport :: Name -> Iface.Alias -> [DtsDecl]
convertAliasExport name (Iface.PublicAlias alias) = [Convert.convertAlias name alias]
convertAliasExport name (Iface.OpaqueAlias (Can.Alias vars _ _ _ _)) = [DtsBrandedType name vars]
convertAliasExport _ (Iface.PrivateAlias _) = []
