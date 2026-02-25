{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Code generation for Terminal commands.
--
-- Provides JavaScript generation functions for dev, prod, and REPL builds.
-- Uses the NEW compiler's pure generation pipeline.
--
-- @since 0.19.1
module Generate
  ( -- * Generation Functions
    dev,
    prod,
    repl,

    -- * Configuration Types
    ReplConfig (..),
  )
where

import qualified AST.Optimized as Opt
import qualified Build
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import Control.Monad.Trans.Except (ExceptT)
import Data.ByteString.Builder (Builder)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import qualified Data.NonEmptyList
import qualified Generate.JavaScript as JS
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode

-- | Task monad for generation errors.
type Task a = ExceptT String IO a

-- | Configuration for REPL code generation.
data ReplConfig = ReplConfig
  { _replConfigAnsi :: !Bool
  , _replConfigName :: !Name.Name
  }
  deriving (Eq, Show)

-- | Generate development build.
--
-- Generates JavaScript optimized for development speed.
-- No type information or optimization.
dev ::
  FilePath ->
  Details.Details ->
  Build.Artifacts ->
  Task Builder
dev _root _details artifacts = do
  let mode = Mode.Dev Nothing False False
  pure (generateJS mode artifacts)

-- | Generate production build.
--
-- Generates optimized JavaScript for production deployment.
-- Includes field name shortening and dead code elimination.
prod ::
  FilePath ->
  Details.Details ->
  Build.Artifacts ->
  Task Builder
prod _root _details artifacts = do
  let globalGraph = extractGlobalGraph artifacts
  let mode = Mode.Prod (Mode.shortenFieldNames globalGraph) False False StringPool.emptyPool
  pure (generateJS mode artifacts)

-- | Generate REPL evaluation code.
--
-- Generates JavaScript for interactive REPL evaluation.
repl ::
  FilePath ->
  Details.Details ->
  ReplConfig ->
  Build.Artifacts ->
  Task Builder
repl _root _details _config artifacts = do
  let mode = Mode.Dev Nothing False False
  pure (generateJS mode artifacts)

-- Helper: Generate JavaScript from artifacts.
generateJS :: Mode.Mode -> Build.Artifacts -> Builder
generateJS mode artifacts =
  let globalGraph = extractGlobalGraph artifacts
      mains = extractMains artifacts
      ffiInfo = artifacts ^. Build.artifactsFFIInfo
      (jsBuilder, _sourceMap) = JS.generate mode globalGraph mains ffiInfo
   in jsBuilder

-- | Extract the GlobalGraph from build artifacts.
--
-- Uses the pre-built global graph stored in the artifacts, which already
-- contains merged dependency package objects (kernel modules, etc.) and
-- locally compiled module objects. The Compiler merges these at build
-- time so code generation can look up any referenced node.
extractGlobalGraph :: Build.Artifacts -> Opt.GlobalGraph
extractGlobalGraph artifacts =
  mergeLocalIntoGlobal (artifacts ^. Build.artifactsGlobalGraph) localModuleNodes
  where
    localModuleNodes = combineModuleGraphs (artifacts ^. Build.artifactsModules)

-- | Merge locally compiled module nodes into the dependency global graph.
--
-- The stored global graph from 'Compiler.hs' may already contain these,
-- but merging again ensures freshly compiled modules override stale
-- entries.
mergeLocalIntoGlobal :: Opt.GlobalGraph -> Map.Map Opt.Global Opt.Node -> Opt.GlobalGraph
mergeLocalIntoGlobal (Opt.GlobalGraph depNodes depFields depLocs) localNodes =
  Opt.GlobalGraph (Map.union localNodes depNodes) depFields depLocs

-- | Combine module graphs into global nodes.
combineModuleGraphs :: [Build.Module] -> Map.Map Opt.Global Opt.Node
combineModuleGraphs modules =
  Map.unions [nodes | Build.Fresh _name _iface (Opt.LocalGraph _ nodes _ _) <- modules]

-- Helper: Extract mains from artifacts.
extractMains :: Build.Artifacts -> Map.Map ModuleName.Canonical Opt.Main
extractMains artifacts =
  let pkg = artifacts ^. Build.artifactsName
      modules = artifacts ^. Build.artifactsModules
      roots = artifacts ^. Build.artifactsRoots
   in gatherMains pkg modules roots

-- Helper: Gather mains from roots and modules.
gatherMains ::
  Pkg.Name ->
  [Build.Module] ->
  Data.NonEmptyList.List Build.Root ->
  Map.Map ModuleName.Canonical Opt.Main
gatherMains pkg modules roots =
  let mainList = Maybe.mapMaybe (extractMainFromRoot pkg modules) (toList roots)
   in Map.fromList mainList

-- Helper: Extract main from a single root.
extractMainFromRoot ::
  Pkg.Name ->
  [Build.Module] ->
  Build.Root ->
  Maybe (ModuleName.Canonical, Opt.Main)
extractMainFromRoot pkg _modules root = case root of
  Build.Inside _name -> Nothing
  Build.Outside name _iface (Opt.LocalGraph maybeMain _ _ _) ->
    case maybeMain of
      Just main -> Just (ModuleName.Canonical pkg name, main)
      Nothing -> Nothing

toList :: Data.NonEmptyList.List a -> [a]
toList (Data.NonEmptyList.List x xs) = x : xs
