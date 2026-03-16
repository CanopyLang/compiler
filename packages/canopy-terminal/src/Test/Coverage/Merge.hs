{-# LANGUAGE OverloadedStrings #-}

-- | Merge multiple coverage report files into a single combined report.
--
-- Supports merging Istanbul JSON and LCOV format files. When the same
-- module\/point appears in multiple files, hit counts are summed.
-- Disjoint modules are unioned.
--
-- @since 0.19.2
module Test.Coverage.Merge
  ( MergeError (..),
    mergeIstanbulFiles,
    mergeIstanbulValues,
    mergeLCOVFiles,
  )
where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KM
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Map.Strict as Map

-- | Errors that can occur during coverage merging.
--
-- @since 0.19.2
data MergeError
  = FileNotFound !FilePath
  | ParseError !FilePath !String
  | EmptyInput
  deriving (Eq, Show)

-- | Read and merge multiple Istanbul JSON coverage files.
--
-- Each file should contain a JSON object with @fnMap@, @f@, @branchMap@,
-- @b@, @s@, @statementMap@ keys. Hit count maps (@f@, @b@, @s@) are
-- summed for matching keys; metadata maps are unioned.
--
-- @since 0.19.2
mergeIstanbulFiles :: [FilePath] -> IO (Either MergeError Aeson.Value)
mergeIstanbulFiles [] = pure (Left EmptyInput)
mergeIstanbulFiles paths = do
  results <- mapM readIstanbulFile paths
  pure (sequence results >>= mergeIstanbulValues)

-- | Read a single Istanbul JSON file.
readIstanbulFile :: FilePath -> IO (Either MergeError Aeson.Value)
readIstanbulFile path = do
  contents <- LBS.readFile path
  case Aeson.eitherDecode contents of
    Left err -> pure (Left (ParseError path err))
    Right val -> pure (Right val)

-- | Merge multiple Istanbul JSON values by summing hit counts.
--
-- For hit count maps (@f@, @b@, @s@), matching keys have their values
-- summed. For metadata maps (@fnMap@, @branchMap@, @statementMap@),
-- entries are unioned (later entries take precedence for duplicates).
--
-- @since 0.19.2
mergeIstanbulValues :: [Aeson.Value] -> Either MergeError Aeson.Value
mergeIstanbulValues [] = Left EmptyInput
mergeIstanbulValues [single] = Right single
mergeIstanbulValues (first : rest) =
  Right (List.foldl' mergeTwo first rest)

-- | Merge two Istanbul JSON objects.
mergeTwo :: Aeson.Value -> Aeson.Value -> Aeson.Value
mergeTwo (Aeson.Object a) (Aeson.Object b) =
  Aeson.Object (KM.unionWith mergeField a b)
mergeTwo a _ = a

-- | Merge a single field: sum for hit maps, union for metadata maps.
mergeField :: Aeson.Value -> Aeson.Value -> Aeson.Value
mergeField (Aeson.Object a) (Aeson.Object b) =
  Aeson.Object (KM.unionWith sumValues a b)
mergeField a _ = a

-- | Sum two numeric JSON values.
sumValues :: Aeson.Value -> Aeson.Value -> Aeson.Value
sumValues (Aeson.Number a) (Aeson.Number b) =
  Aeson.Number (a + b)
sumValues a _ = a

-- | Read and merge multiple LCOV coverage files.
--
-- Parses each file into a map of @(module, line) -> hitCount@, sums
-- hit counts for matching entries, then re-emits valid LCOV.
--
-- @since 0.19.2
mergeLCOVFiles :: [FilePath] -> IO (Either MergeError Builder)
mergeLCOVFiles [] = pure (Left EmptyInput)
mergeLCOVFiles paths = do
  contents <- mapM readLCOVFile paths
  case sequence contents of
    Left err -> pure (Left err)
    Right lcovTexts -> pure (Right (mergeLCOVTexts lcovTexts))

-- | Read a single LCOV file.
readLCOVFile :: FilePath -> IO (Either MergeError String)
readLCOVFile path = do
  contents <- readFile path
  pure (Right contents)

-- | Merge multiple LCOV text contents.
--
-- Parses DA lines into a map of @(sourceFile, lineNo) -> hitCount@,
-- sums matching entries, and re-emits the merged LCOV output.
mergeLCOVTexts :: [String] -> Builder
mergeLCOVTexts texts =
  emitMergedLCOV (foldl mergeLCOVParsed Map.empty (map parseLCOV texts))

-- | Parsed LCOV data: map from source file to map of line number to hit count.
type LCOVData = Map.Map String (Map.Map Int Int)

-- | Parse LCOV text into structured data.
parseLCOV :: String -> LCOVData
parseLCOV = go Map.empty "" . lines
  where
    go acc _ [] = acc
    go acc currentSF (line : rest)
      | "SF:" `List.isPrefixOf` line =
          go acc (drop 3 line) rest
      | "DA:" `List.isPrefixOf` line =
          let daContent = drop 3 line
              acc' = maybe acc (\(lineNo, hitCount) -> addDA acc currentSF lineNo hitCount) (parseDA daContent)
           in go acc' currentSF rest
      | otherwise = go acc currentSF rest

    addDA acc sf lineNo hitCount =
      Map.insertWith (Map.unionWith (+)) sf (Map.singleton lineNo hitCount) acc

-- | Parse a DA line content like @\"5,3\"@ into @(lineNo, hitCount)@.
parseDA :: String -> Maybe (Int, Int)
parseDA s =
  case break (== ',') s of
    (lineStr, ',' : hitStr) ->
      case (reads lineStr, reads hitStr) of
        ([(lineNo, "")], [(hitCount, "")]) -> Just (lineNo, hitCount)
        _ -> Nothing
    _ -> Nothing

-- | Merge two parsed LCOV datasets by summing hit counts.
mergeLCOVParsed :: LCOVData -> LCOVData -> LCOVData
mergeLCOVParsed = Map.unionWith (Map.unionWith (+))

-- | Emit merged LCOV data as a Builder.
emitMergedLCOV :: LCOVData -> Builder
emitMergedLCOV = Map.foldlWithKey' emitFile mempty
  where
    emitFile acc sf lineMap =
      acc
        <> BB.stringUtf8 "TN:\n"
        <> BB.stringUtf8 "SF:"
        <> BB.stringUtf8 sf
        <> BB.char7 '\n'
        <> Map.foldlWithKey' emitDA mempty lineMap
        <> BB.stringUtf8 "LF:"
        <> BB.intDec (Map.size lineMap)
        <> BB.char7 '\n'
        <> BB.stringUtf8 "LH:"
        <> BB.intDec (Map.size (Map.filter (> 0) lineMap))
        <> BB.char7 '\n'
        <> BB.stringUtf8 "end_of_record\n"

    emitDA acc lineNo hitCount =
      acc
        <> BB.stringUtf8 "DA:"
        <> BB.intDec lineNo
        <> BB.char7 ','
        <> BB.intDec hitCount
        <> BB.char7 '\n'
