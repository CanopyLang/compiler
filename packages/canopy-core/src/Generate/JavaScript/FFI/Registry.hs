{-# LANGUAGE OverloadedStrings #-}

-- | Function-level FFI registry for tree-shaking.
--
-- Splits monolithic FFI JavaScript files into individually addressable
-- definitions. Each definition has its JS AST statements and automatically
-- computed dependencies on other definitions within the same FFI file.
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
-- Blocks are stored as @[JSStatement]@ AST nodes. Rendering to 'Builder'
-- only happens at the final emit step, eliminating the double-parse
-- anti-pattern previously needed for debug-branch elimination in production.
--
-- @since 0.20.2
module Generate.JavaScript.FFI.Registry
  ( -- * Types
    FFIBlockId (..),
    FFIBlock (..),
    FFIRegistryResult (..),

    -- * Registry building
    buildFFIRegistry,
    buildFFIRegistryFull,

    -- * Tree-shaking
    closeFFIDeps,
    closeFFICrossFileDeps,
    emitNeededBlocks,
    collectNeededStatements,

    -- * Rendering
    renderStatements,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Blaze.ByteString.Builder as Blaze
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified Generate.JavaScript.FFI.JSAnalysis as JSAnalysis
import qualified Language.JavaScript.Parser.AST as JSAST
import qualified Language.JavaScript.Pretty.Printer as JSPrint
import qualified Language.JavaScript.Process.Minify as JSMinify


-- TYPES

-- | Unique identifier for an FFI block — the declared JS name.
--
-- Examples: @\"text\"@, @\"init\"@, @\"_VirtualDom_render\"@
newtype FFIBlockId = FFIBlockId {_fbidName :: ByteString}
  deriving (Eq, Ord, Show)

-- | A single FFI block with dependency metadata.
--
-- Stores AST statements rather than rendered bytes so that production-mode
-- transformations (debug-branch elimination) can operate on the AST directly
-- without re-parsing. Rendering happens once at final emit time.
data FFIBlock = FFIBlock
  { _fbStatements  :: ![JSAST.JSStatement]
    -- ^ AST statements for this block (the declaration plus any trailing
    -- non-declaration statements that belong to it).
  , _fbJSDoc       :: !(Maybe Text.Text)
    -- ^ Preceding JSDoc comment text, if any (raw lines including @/**@).
  , _fbDeps        :: !(Set FFIBlockId)
    -- ^ Direct dependencies on other blocks in the same FFI file.
  , _fbAllFreeVars :: !(Set ByteString)
    -- ^ All free identifiers referenced by this block (unfiltered).
    -- Used for cross-file dependency resolution.
  , _fbOrder       :: !Int
    -- ^ Original position in the source file (for stable ordering).
  }
  deriving (Show)


-- | Combined result of building an FFI registry from a source file.
--
-- Captures both the per-block registry used for tree-shaking and the
-- full AST needed for the non-tree-shaken (full-file) output path.
-- Both are produced from a single parse pass, avoiding redundant work.
--
-- When the source file fails to parse, both fields are empty; the caller
-- must fall back to emitting the raw 'Text.Text' source in that case.
data FFIRegistryResult = FFIRegistryResult
  { _frrRegistry :: !(Map FFIBlockId FFIBlock)
    -- ^ Per-block registry for tree-shaking. Empty on parse failure.
  , _frrFullAST  :: ![JSAST.JSStatement]
    -- ^ Full program statements for the fallback (non-tree-shaken) path.
    -- Empty on parse failure; callers fall back to raw 'Text' in that case.
  }


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
buildFFIRegistry = _frrRegistry . buildFFIRegistryFull

-- | Build a registry result from FFI content in a single parse pass.
--
-- Returns both the per-block tree-shaking registry and the complete
-- top-level statement list for the full-file emit path. Using one parse
-- for both avoids the redundant parse + render anti-pattern.
buildFFIRegistryFull :: Text.Text -> FFIRegistryResult
buildFFIRegistryFull content =
  case JSAnalysis.parseAllGroups content of
    Nothing                 -> FFIRegistryResult Map.empty []
    Just (allStmts, groups) ->
      FFIRegistryResult (buildFromGroups content groups) allStmts

-- | Build the registry from a parsed list of block groups.
buildFromGroups :: Text.Text -> [JSAnalysis.BlockGroup] -> Map FFIBlockId FFIBlock
buildFromGroups content groups =
  Map.union primaryMap aliasMap
  where
    textLines = Text.lines content
    allNames = Set.fromList (concatMap JSAnalysis.groupDeclNames groups)
    starts = List.map (walkBackJSDocText textLines . JSAnalysis._bgLine) groups
    ends = List.drop 1 starts ++ [length textLines]
    bounds = zip starts ends
    primaryMap = Map.fromList (zipWith (mkEntry textLines allNames) groups bounds)
    aliasMap = buildAliasMap primaryMap groups

-- | Build a single registry entry for a block group.
mkEntry
  :: [Text.Text]
  -> Set ByteString
  -> JSAnalysis.BlockGroup
  -> (Int, Int)
  -> (FFIBlockId, FFIBlock)
mkEntry textLines allNames g (start, _end) =
  (FFIBlockId (JSAnalysis._bgName g), mkBlockFromGroup g allNames jsDoc start)
  where
    docLineCount = JSAnalysis._bgLine g - start
    jsDocLines = List.take docLineCount (List.drop start textLines)
    jsDocText = Text.unlines jsDocLines
    jsDoc = if docLineCount > 0 then Just jsDocText else Nothing

-- | Create an 'FFIBlock' from a parsed group using AST-based dependency analysis.
mkBlockFromGroup
  :: JSAnalysis.BlockGroup -> Set ByteString -> Maybe Text.Text -> Int -> FFIBlock
mkBlockFromGroup g allNames jsDoc order =
  FFIBlock stmts jsDoc deps allFreeVars order
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
-- Given a registry, a prod-mode flag, and a set of needed block IDs
-- (already closed over dependencies), renders their AST statements to
-- 'Builder' in the original file order. Any preceding JSDoc comment is
-- emitted before the rendered statements.
--
-- When @isProd@ is 'True', 'minifyJS' is applied before rendering to strip
-- all whitespace and comments from the output.
emitNeededBlocks :: Bool -> Map FFIBlockId FFIBlock -> Set FFIBlockId -> Builder
emitNeededBlocks isProd reg needed =
  foldMap emitOne ordered
  where
    ordered = sortByOrder (Set.toList needed)
    emitOne bid =
      maybe mempty (renderBlock isProd) (Map.lookup bid reg)
    sortByOrder =
      List.sortOn (\bid -> maybe maxBound _fbOrder (Map.lookup bid reg))

-- | Collect needed block statements in source order without rendering.
--
-- Returns the raw @[JSStatement]@ for the needed blocks so that callers can
-- compose them into a larger AST (e.g. an IIFE body) before rendering,
-- enabling unified minification of the IIFE and its generated bindings as a
-- single program. Any block not present in the registry is silently skipped.
--
-- @since 0.20.4
collectNeededStatements :: Map FFIBlockId FFIBlock -> Set FFIBlockId -> [JSAST.JSStatement]
collectNeededStatements reg needed =
  foldMap _fbStatements ordered
  where
    ordered = List.sortOn _fbOrder candidates
    candidates = [block | bid <- Set.toList needed, Just block <- [Map.lookup bid reg]]

-- | Render a single 'FFIBlock' to 'Builder', including any JSDoc prefix.
--
-- When @isProd@ is 'True', applies 'minifyJS' before rendering.
renderBlock :: Bool -> FFIBlock -> Builder
renderBlock isProd block =
  foldMap renderJSDoc (_fbJSDoc block)
  <> renderStatements isProd (_fbStatements block)
  <> "\n"

-- | Render JSDoc text to 'Builder'.
renderJSDoc :: Text.Text -> Builder
renderJSDoc doc = BB.byteString (TextEnc.encodeUtf8 doc)

-- | Render a list of 'JSStatement' nodes to 'Builder' via the pretty-printer.
--
-- Wraps the statements in a 'JSAST.JSAstProgram' so that the printer
-- produces a top-level program (newline-separated statements) rather than
-- a single expression or statement fragment.
--
-- When @isProd@ is 'True', applies 'minifyJS' to strip whitespace and comments.
renderStatements :: Bool -> [JSAST.JSStatement] -> Builder
renderStatements isProd stmts =
  BB.lazyByteString
    (Blaze.toLazyByteString
      (JSPrint.renderJS ast'))
  where
    ast  = JSAST.JSAstProgram stmts JSAST.JSNoAnnot
    ast' = if isProd then JSMinify.minifyJS ast else ast


-- INTERNAL: JSDOC WALK-BACK (TEXT-BASED)

-- | Walk backwards from a declaration line to find where its JSDoc starts.
--
-- Returns the 0-indexed line at which the JSDoc comment (or other immediately
-- preceding comments/blank lines) begins, so that the block content includes
-- the full documentation block.
walkBackJSDocText :: [Text.Text] -> Int -> Int
walkBackJSDocText _ 0 = 0
walkBackJSDocText allLines declIdx = go (declIdx - 1)
  where
    go idx
      | idx < 0 = 0
      | otherwise =
          let line = allLines !! idx
              stripped = Text.dropWhile (== ' ') line
           in if isJSDocOrComment stripped || Text.null (Text.strip line)
                then go (idx - 1)
                else idx + 1
    isJSDocOrComment l =
      Text.isPrefixOf "/**" l
        || Text.isPrefixOf " *" l
        || Text.isPrefixOf "*/" l
        || Text.isPrefixOf "* " l
        || Text.isPrefixOf "*\n" l
        || Text.isPrefixOf "//" l
        || l == "*"
