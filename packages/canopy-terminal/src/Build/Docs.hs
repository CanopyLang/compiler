{-# LANGUAGE OverloadedStrings #-}

-- | Documentation extraction from build artifacts.
--
-- This module generates 'Canopy.Docs.Documentation' from build artifacts by
-- extracting type information stored in each compiled module's 'Interface.Interface'.
-- Since interfaces contain all exported types, unions, aliases, and binops,
-- they contain everything needed to produce structural documentation.
--
-- Comments are left blank because the compiler interface layer does not
-- preserve source-level doc comments — only the type information survives
-- the compilation pipeline into artifacts. Callers that need rich comments
-- must use 'Canopy.Docs.fromModule' directly with the canonical AST.
--
-- == Usage
--
-- @
-- artifacts <- Build.fromExposed config exposedModules
-- let docs = docsFromArtifacts artifacts
-- @
--
-- @since 0.19.1
module Build.Docs
  ( -- * Documentation Extraction
    docsFromArtifacts,

    -- * Module-level Extraction
    docsModuleFromInterface,
  )
where

import qualified AST.Canonical as Can
import qualified Build.Artifacts as Build
import qualified Canopy.Compiler.Type.Extract as Extract
import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Docs as Docs
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import qualified Json.String as Json

-- | Extract full documentation from compiled build artifacts.
--
-- Iterates over all 'Build.Fresh' modules in the artifact set and
-- constructs a 'Docs.Module' for each one from its 'Interface.Interface'.
-- The resulting map is keyed by the raw module name.
--
-- @since 0.19.1
docsFromArtifacts :: Build.Artifacts -> Docs.Documentation
docsFromArtifacts artifacts =
  Map.fromList (map moduleToDocsPair (Build._artifactsModules artifacts))

-- | Convert a single 'Build.Module' to a documentation map entry.
--
-- @since 0.19.1
moduleToDocsPair :: Build.Module -> (Name.Name, Docs.Module)
moduleToDocsPair (Build.Fresh modName iface _) =
  (modName, docsModuleFromInterface modName iface)

-- | Build a 'Docs.Module' from a module name and its interface.
--
-- All documentation comments are left blank because the 'Interface.Interface'
-- representation does not carry source-level comment text.
--
-- @since 0.19.1
docsModuleFromInterface :: ModuleName.Raw -> Interface.Interface -> Docs.Module
docsModuleFromInterface modName (Interface.Interface _ values unions aliases binops) =
  Docs.Module
    { Docs._name = modName
    , Docs._comment = emptyComment
    , Docs._unions = Map.mapMaybe unionToDocs unions
    , Docs._aliases = Map.mapMaybe aliasToDocs aliases
    , Docs._values = Map.map annotationToValue values
    , Docs._binops = Map.map binopToDocs binops
    }

-- | Convert an 'Interface.Union' to a 'Docs.Union', discarding private unions.
--
-- Returns 'Nothing' for 'PrivateUnion' entries, which are filtered
-- from the documentation output.
--
-- @since 0.19.1
unionToDocs :: Interface.Union -> Maybe Docs.Union
unionToDocs iUnion =
  fmap buildDocsUnion (Interface.toPublicUnion iUnion)

-- | Construct a 'Docs.Union' from a canonical union.
--
-- @since 0.19.1
buildDocsUnion :: Can.Union -> Docs.Union
buildDocsUnion (Can.Union tvars ctors _ _) =
  Docs.Union emptyComment tvars (map ctorPair ctors)

-- | Convert a canonical constructor to a name/types pair.
--
-- @since 0.19.1
ctorPair :: Can.Ctor -> (Name.Name, [Type.Type])
ctorPair (Can.Ctor name _ _ args) =
  (name, map Extract.fromType args)

-- | Convert an 'Interface.Alias' to a 'Docs.Alias', discarding private aliases.
--
-- Returns 'Nothing' for 'PrivateAlias' entries, which are filtered
-- from the documentation output.
--
-- @since 0.19.1
aliasToDocs :: Interface.Alias -> Maybe Docs.Alias
aliasToDocs iAlias =
  fmap buildDocsAlias (Interface.toPublicAlias iAlias)

-- | Construct a 'Docs.Alias' from a canonical alias.
--
-- @since 0.19.1
buildDocsAlias :: Can.Alias -> Docs.Alias
buildDocsAlias (Can.Alias tvars tipe) =
  Docs.Alias emptyComment tvars (Extract.fromType tipe)

-- | Convert a 'Can.Annotation' to a 'Docs.Value'.
--
-- @since 0.19.1
annotationToValue :: Can.Annotation -> Docs.Value
annotationToValue annotation =
  Docs.Value emptyComment (Extract.fromAnnotation annotation)

-- | Convert an 'Interface.Binop' to a 'Docs.Binop'.
--
-- @since 0.19.1
binopToDocs :: Interface.Binop -> Docs.Binop
binopToDocs (Interface.Binop _ annotation assoc prec) =
  Docs.Binop emptyComment (Extract.fromAnnotation annotation) assoc prec

-- | An empty documentation comment.
--
-- Used when the interface layer does not carry source-level comment text.
-- The type 'Json.String' is what 'Docs.Module' uses for its comment fields.
--
-- @since 0.19.1
emptyComment :: Json.String
emptyComment = Json.fromChars ""
