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
-- ~200 lines (~5KB) instead of the full file.
--
-- The splitting strategy:
--
--   1. Scan for top-level @var@ and @function@ declarations
--   2. Split at declaration boundaries, grouping preceding JSDoc\/comments
--   3. Compute inter-function dependencies via identifier scanning
--   4. Provide transitive closure for dependency resolution
--
-- @since 0.20.2
module Generate.JavaScript.FFI.Registry
  ( -- * Types
    FFIBlockId (..)
  , FFIBlock (..)

    -- * Registry building
  , buildFFIRegistry

    -- * Tree-shaking
  , closeFFIDeps
  , emitNeededBlocks
  ) where

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
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import Data.Word (Word8)


-- TYPES

-- | Unique identifier for an FFI block — the declared JS name.
--
-- Examples: @\"text\"@, @\"init\"@, @\"_VirtualDom_render\"@
newtype FFIBlockId = FFIBlockId { _fbidName :: ByteString }
  deriving (Eq, Ord, Show)

-- | A single FFI block with dependency metadata.
data FFIBlock = FFIBlock
  { _fbContent :: !ByteString
    -- ^ Raw JS source including any preceding JSDoc comment.
  , _fbDeps :: !(Set FFIBlockId)
    -- ^ Direct dependencies on other blocks in the same FFI file.
  , _fbOrder :: !Int
    -- ^ Original position in the source file (for stable ordering).
  } deriving (Show)


-- REGISTRY BUILDING

-- | Build a registry of individually addressable blocks from FFI content.
--
-- Parses the FFI JavaScript text, splits at declaration boundaries,
-- computes inter-block dependencies, and returns a map from block ID
-- to block definition.
buildFFIRegistry :: Text.Text -> Map FFIBlockId FFIBlock
buildFFIRegistry content =
  Map.fromList
    [ (FFIBlockId name, mkBlock name block order allNames)
    | (name, block, order) <- entries
    ]
  where
    contentBs = TextEnc.encodeUtf8 content
    entries = splitFFI contentBs
    allNames = Set.fromList [name | (name, _, _) <- entries]

-- | Create an 'FFIBlock' from a raw block, computing dependencies.
mkBlock :: ByteString -> ByteString -> Int -> Set ByteString -> FFIBlock
mkBlock selfName content order allNames =
  FFIBlock content deps order
  where
    refs = extractIdentifiers content
    deps = Set.map FFIBlockId
      (Set.delete selfName (Set.intersection refs allNames))


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
          let new = Set.difference pending visited
              visited' = Set.union visited new
              directDeps = foldMap depsOf (Set.toList new)
           in go visited' directDeps
    depsOf bid =
      maybe Set.empty _fbDeps (Map.lookup bid reg)

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


-- INTERNAL: FFI SPLITTING

-- | Split an FFI JS file into individual blocks.
--
-- Each top-level @var@ or @function@ declaration starts a new block.
-- Preceding JSDoc comments and blank lines are grouped with the
-- declaration they precede.
--
-- Returns @[(blockName, fullContent, lineIndex)]@.
splitFFI :: ByteString -> [(ByteString, ByteString, Int)]
splitFFI content =
  buildEntries linesVec declStarts totalLines
  where
    rawLines = BS8.lines content
    linesVec = rawLines
    totalLines = length rawLines
    declStarts = findDeclStarts rawLines 0

-- | Find line indices of all top-level declarations.
findDeclStarts :: [ByteString] -> Int -> [(Int, ByteString)]
findDeclStarts [] _ = []
findDeclStarts (line : rest) idx
  | isTopLevelDecl line = (idx, line) : findDeclStarts rest (idx + 1)
  | otherwise = findDeclStarts rest (idx + 1)

-- | Build entries by slicing lines between declarations.
--
-- For each declaration, we include any preceding JSDoc comment block.
buildEntries
  :: [ByteString]
  -> [(Int, ByteString)]
  -> Int
  -> [(ByteString, ByteString, Int)]
buildEntries _ [] _ = []
buildEntries allLines ((startIdx, startLine) : rest) totalLines =
  case extractDeclName startLine of
    "" -> buildEntries allLines rest totalLines
    name ->
      let jsDocStart = walkBackJSDoc startIdx allLines
          endIdx = case rest of
            ((nextIdx, _) : _) -> walkBackJSDoc nextIdx allLines
            [] -> totalLines
          blockLines = take (endIdx - jsDocStart) (drop jsDocStart allLines)
          block = BS8.unlines blockLines
       in (name, block, jsDocStart) : buildEntries allLines rest totalLines

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

-- | Check if a line starts a top-level declaration.
--
-- Must start at column 0 (no indentation) and be either @var@ or @function@.
isTopLevelDecl :: ByteString -> Bool
isTopLevelDecl line =
  BS8.isPrefixOf "var " line || BS8.isPrefixOf "function " line

-- | Extract the declared name from a @var@ or @function@ line.
extractDeclName :: ByteString -> ByteString
extractDeclName line
  | Just rest <- BS8.stripPrefix "var " line =
      BS8.takeWhile isIdentChar rest
  | Just rest <- BS8.stripPrefix "function " line =
      BS8.takeWhile isIdentChar rest
  | otherwise = ""


-- INTERNAL: IDENTIFIER SCANNING

-- | Extract all identifier-like tokens from JS source.
--
-- Finds both @_Module_name@ style tokens and plain identifiers.
-- Only extracts tokens that start at a word boundary (preceding
-- character is not an identifier character).
extractIdentifiers :: ByteString -> Set ByteString
extractIdentifiers bs = go 0 Set.empty
  where
    len = BS.length bs
    go i acc
      | i >= len = acc
      | isIdentStart (BS.index bs i)
        , i == 0 || not (isIdentByte (BS.index bs (i - 1))) =
          let end = skipIdent (i + 1)
              token = BS.take (end - i) (BS.drop i bs)
           in go end (Set.insert token acc)
      | otherwise = go (i + 1) acc
    skipIdent j
      | j >= len = j
      | isIdentByte (BS.index bs j) = skipIdent (j + 1)
      | otherwise = j
    isIdentStart b =
      (b >= 0x61 && b <= 0x7A) -- a-z
        || (b >= 0x41 && b <= 0x5A) -- A-Z
        || b == 0x5F -- _
        || b == 0x24 -- $


-- INTERNAL: CHARACTER CLASSIFICATION

-- | Check if a byte is a valid JavaScript identifier character.
isIdentByte :: Word8 -> Bool
isIdentByte b =
  (b >= 0x61 && b <= 0x7A) -- a-z
    || (b >= 0x41 && b <= 0x5A) -- A-Z
    || (b >= 0x30 && b <= 0x39) -- 0-9
    || b == 0x5F -- _
    || b == 0x24 -- $

-- | Check if a 'Char' is a valid JavaScript identifier character.
isIdentChar :: Char -> Bool
isIdentChar c =
  (c >= 'a' && c <= 'z')
    || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9')
    || c == '_'
    || c == '$'
