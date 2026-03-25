{-# LANGUAGE OverloadedStrings #-}

-- | Function-level FFI registry for tree-shaking.
--
-- Splits monolithic FFI JavaScript files into individually addressable
-- definitions. Each definition has its JS source and automatically computed
-- dependencies on other definitions within the same FFI file.
--
-- This enables the code generator to emit only the FFI functions that are
-- actually referenced, achieving function-level tree-shaking for FFI files.
-- For the VirtualDom FFI (2639 lines, 70KB), a hello-world app only needs
-- ~8 blocks (~80 lines) instead of the full file.
--
-- The splitting strategy uses the @language-javascript@ AST (via
-- 'Generate.JavaScript.FFI.JSAnalysis') for scope-aware free-variable
-- extraction. String literals are distinct AST nodes that contribute no
-- dependencies, eliminating false edges from patterns like @args[\'node\']@.
--
-- @since 0.20.2
module Generate.JavaScript.FFI.Registry
  ( -- * Types
    FFIBlockId (..),
    FFIBlock (..),

    -- * Registry building
    buildFFIRegistry,

    -- * Tree-shaking
    closeFFIDeps,
    closeFFICrossFileDeps,
    emitNeededBlocks,
  )
where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text.Encoding as TextEnc
import qualified Data.Text as Text
import qualified Generate.JavaScript.FFI.JSAnalysis as JSAnalysis


-- TYPES

-- | Unique identifier for an FFI block — the declared JS name.
--
-- Examples: @\"text\"@, @\"init\"@, @\"_VirtualDom_render\"@
newtype FFIBlockId = FFIBlockId {_fbidName :: ByteString}
  deriving (Eq, Ord, Show)

-- | A single FFI block with dependency metadata.
data FFIBlock = FFIBlock
  { _fbContent :: !ByteString
    -- ^ Raw JS source including any preceding JSDoc comment.
  , _fbDeps :: !(Set FFIBlockId)
    -- ^ Direct dependencies on other blocks in the same FFI file.
  , _fbAllFreeVars :: !(Set ByteString)
    -- ^ All free identifiers referenced by this block (unfiltered).
    -- Used for cross-file dependency resolution.
  , _fbOrder :: !Int
    -- ^ Original position in the source file (for stable ordering).
  }
  deriving (Show)


-- REGISTRY BUILDING

-- | Build a registry of individually addressable blocks from FFI content.
--
-- Parses the FFI JavaScript text using 'JSAnalysis.parseBlockGroups',
-- computes AST-based inter-block dependencies, and returns a map from
-- block ID to block definition.
--
-- Returns an empty map on parse failure, which causes the caller to
-- fall back to emitting the full file without tree-shaking.
--
-- When a @var@ declaration uses comma-separated names (e.g.
-- @var A = 0, B = 1;@), each name is registered as an alias for the
-- same block.
buildFFIRegistry :: Text.Text -> Map FFIBlockId FFIBlock
buildFFIRegistry content =
  maybe Map.empty (buildFromGroups content) (JSAnalysis.parseBlockGroups content)

-- | Build the registry from a parsed list of block groups.
buildFromGroups :: Text.Text -> [JSAnalysis.BlockGroup] -> Map FFIBlockId FFIBlock
buildFromGroups content groups =
  Map.union primaryMap aliasMap
  where
    rawLines = BS8.lines (TextEnc.encodeUtf8 content)
    totalLines = length rawLines
    allNames = Set.fromList (concatMap JSAnalysis.groupDeclNames groups)
    bounds = groupBounds groups rawLines totalLines
    primaryMap = Map.fromList (zipWith (mkEntry rawLines allNames) groups bounds)
    aliasMap = buildAliasMap primaryMap groups

-- | Compute (start, end) line index bounds for each group's content.
--
-- Each group's content spans from its JSDoc walk-back start to the
-- walk-back start of the next group (or end of file).
groupBounds :: [JSAnalysis.BlockGroup] -> [ByteString] -> Int -> [(Int, Int)]
groupBounds groups rawLines totalLines =
  zip starts ends
  where
    starts = List.map (\g -> walkBackJSDoc (JSAnalysis._bgLine g) rawLines) groups
    ends = List.drop 1 starts ++ [totalLines]

-- | Build a single registry entry for a block group.
mkEntry
  :: [ByteString]
  -> Set ByteString
  -> JSAnalysis.BlockGroup
  -> (Int, Int)
  -> (FFIBlockId, FFIBlock)
mkEntry rawLines allNames g (start, end) =
  (FFIBlockId (JSAnalysis._bgName g), mkBlockFromGroup g allNames blockContent start)
  where
    blockContent = BS8.unlines (List.take (end - start) (List.drop start rawLines))

-- | Create an 'FFIBlock' from a parsed group using AST-based dependency analysis.
mkBlockFromGroup
  :: JSAnalysis.BlockGroup -> Set ByteString -> ByteString -> Int -> FFIBlock
mkBlockFromGroup g allNames content order =
  FFIBlock content deps allFreeVars order
  where
    stmts = JSAnalysis._bgStatements g
    selfName = JSAnalysis._bgName g
    allFreeVars = JSAnalysis.allFreeVarsInGroup stmts
    localFreeVars = JSAnalysis.freeVarsInGroup allNames stmts
    deps = Set.map FFIBlockId (Set.delete selfName localFreeVars)

-- | Build the alias map for comma-separated @var@ declarations.
--
-- For @var A = 0, B = 1@, registers @B@ as an alias pointing to
-- the same 'FFIBlock' as @A@.
buildAliasMap
  :: Map FFIBlockId FFIBlock -> [JSAnalysis.BlockGroup] -> Map FFIBlockId FFIBlock
buildAliasMap primaryMap groups =
  Map.fromList (concatMap mkAliases groups)
  where
    mkAliases g =
      case JSAnalysis.groupDeclNames g of
        (primary : aliases) ->
          maybe [] (mkAliasEntries aliases) (Map.lookup (FFIBlockId primary) primaryMap)
        [] -> []
    mkAliasEntries aliases block =
      [ (FFIBlockId alias, block)
      | alias <- aliases
      , not (Map.member (FFIBlockId alias) primaryMap)
      ]


-- TREE-SHAKING

-- | Compute the transitive closure of FFI block dependencies.
--
-- Given a seed set of needed blocks, repeatedly expands by adding
-- each block's direct dependencies until no new blocks are discovered.
closeFFIDeps :: Map FFIBlockId FFIBlock -> Set FFIBlockId -> Set FFIBlockId
closeFFIDeps reg seeds = go Set.empty seeds
  where
    go visited pending
      | Set.null pending = visited
      | otherwise =
          go visited' directDeps
          where
            new = Set.difference pending visited
            visited' = Set.union visited new
            directDeps = foldMap depsOf (Set.toList new)
    depsOf bid =
      maybe Set.empty _fbDeps (Map.lookup bid reg)

-- | Compute transitive closure of FFI block dependencies across multiple files.
--
-- Given per-file registries and initial seed blocks, iteratively resolves
-- cross-file references until stable. When a needed block in file A references
-- an identifier defined in file B, that block is added as a seed for file B.
--
-- Keyed by file path (not alias name) to avoid collisions when multiple
-- modules share the same FFI alias (e.g. Platform, Platform.Cmd, Platform.Sub).
--
-- Most cross-file references resolve in 2 iterations (direct refs are rarely chained).
closeFFICrossFileDeps
  :: Map String (Map FFIBlockId FFIBlock)
  -> Map String (Set FFIBlockId)
  -> Map String (Set FFIBlockId)
closeFFICrossFileDeps registries initialSeeds =
  closeFinal (iterateSeeds initialSeeds)
  where
    crossFileIndex = buildCrossFileIndex registries
    closeFinal = Map.mapWithKey closeLocal
    closeLocal fileKey blocks =
      maybe blocks (`closeFFIDeps` blocks) (Map.lookup fileKey registries)
    iterateSeeds seeds =
      let closed = Map.mapWithKey closeLocal seeds
          newCross = collectCrossSeeds closed
          merged = Map.unionWith Set.union seeds newCross
       in if merged == seeds then seeds else iterateSeeds merged
    collectCrossSeeds = Map.foldlWithKey' findCrossRefs Map.empty
    findCrossRefs acc fileKey blocks =
      maybe acc (resolveUnresolved acc fileKey blocks) (Map.lookup fileKey registries)
    resolveUnresolved acc fileKey blocks reg =
      Set.foldl' (addCrossRef fileKey) acc crossRefs
      where
        crossRefs = Set.map FFIBlockId (unresolvedRefs reg blocks)
    addCrossRef sourceFile acc bid =
      case Map.lookup bid crossFileIndex of
        Just targetFile
          | targetFile /= sourceFile ->
              Map.insertWith Set.union targetFile (Set.singleton bid) acc
        _ -> acc

-- | Build index mapping each block ID to the file path that defines it.
buildCrossFileIndex
  :: Map String (Map FFIBlockId FFIBlock)
  -> Map FFIBlockId String
buildCrossFileIndex =
  Map.foldlWithKey' addFile Map.empty
  where
    addFile acc fileKey reg =
      Map.foldlWithKey' (\a bid _ -> Map.insert bid fileKey a) acc reg

-- | Extract identifiers referenced by needed blocks that aren't defined locally.
--
-- Uses the unfiltered free-variable set ('_fbAllFreeVars') stored in each
-- block, so cross-file references to identifiers defined in other FFI files
-- are included even though they were excluded from '_fbDeps'.
unresolvedRefs :: Map FFIBlockId FFIBlock -> Set FFIBlockId -> Set ByteString
unresolvedRefs localRegistry neededBlocks =
  Set.difference allRefs localBlockNames
  where
    allRefs = foldMap extractBlockRefs (Set.toList neededBlocks)
    extractBlockRefs bid =
      maybe Set.empty _fbAllFreeVars (Map.lookup bid localRegistry)
    localBlockNames = Set.map _fbidName (Map.keysSet localRegistry)

-- | Emit needed blocks in original source order.
--
-- Given a registry and a set of needed block IDs (already closed
-- over dependencies), emits their content in the original file order.
emitNeededBlocks :: Map FFIBlockId FFIBlock -> Set FFIBlockId -> Builder
emitNeededBlocks reg needed =
  foldMap emitOne ordered
  where
    ordered = sortByOrder (Set.toList needed)
    emitOne bid =
      maybe mempty (BB.byteString . _fbContent) (Map.lookup bid reg)
    sortByOrder =
      List.sortOn (\bid -> maybe maxBound _fbOrder (Map.lookup bid reg))


-- INTERNAL: JSDOC WALK-BACK

-- | Walk backwards from a declaration to find where its JSDoc starts.
walkBackJSDoc :: Int -> [ByteString] -> Int
walkBackJSDoc 0 _ = 0
walkBackJSDoc declIdx allLines =
  go (declIdx - 1)
  where
    go idx
      | idx < 0 = 0
      | otherwise =
          let line = allLines !! idx
           in if isJSDocOrComment line || BS.null (BS8.strip line)
                then go (idx - 1)
                else idx + 1
    isJSDocOrComment l =
      let stripped = BS8.dropWhile (== ' ') l
       in BS8.isPrefixOf "/**" stripped
            || BS8.isPrefixOf " *" stripped
            || BS8.isPrefixOf "*/" stripped
            || BS8.isPrefixOf "* " stripped
            || BS8.isPrefixOf "*\n" stripped
            || BS8.isPrefixOf "//" stripped
            || stripped == "*"
