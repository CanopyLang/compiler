{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Coverage command handler for the @canopy coverage@ subcommands.
--
-- Provides merging of multiple coverage report files and format conversion.
--
-- == Usage
--
-- @
-- canopy coverage merge cov-unit.json cov-integration.json -o merged.json
-- canopy coverage report merged.json --format terminal
-- @
--
-- @since 0.19.2
module CoverageCmd
  ( run,
    Flags (..),
    coverageFileParser,
    formatParser,
    outputParser,
  )
where

import Control.Lens ((^.))
import Control.Lens.TH (makeLenses)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Reporting.Doc.ColorQQ (c)
import qualified Terminal
import qualified Terminal.Print as Print
import qualified Test.Coverage.Merge as Merge

-- | Flags for the coverage command.
--
-- @since 0.19.2
data Flags = Flags
  { -- | Output file path for merged coverage
    _coverageOutput :: !(Maybe String),
    -- | Output format for report generation
    _coverageFormat :: !(Maybe String)
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Main entry point for the coverage command.
--
-- When given input files, merges them and writes to the output path.
--
-- @since 0.19.2
run :: [FilePath] -> Flags -> IO ()
run [] _ = do
  Print.printErrLn [c|{red|Error:} No input files specified.|]
  Print.println [c|Usage: canopy coverage merge file1.json file2.json -o merged.json|]
run paths flags =
  case flags ^. coverageFormat of
    Just "lcov" -> mergeLCOV paths flags
    _ -> mergeIstanbul paths flags

-- | Merge Istanbul JSON files and write the result.
mergeIstanbul :: [FilePath] -> Flags -> IO ()
mergeIstanbul paths flags = do
  result <- Merge.mergeIstanbulFiles paths
  case result of
    Left err -> reportMergeError err
    Right merged -> writeOutput flags merged

-- | Merge LCOV files and write the result.
mergeLCOV :: [FilePath] -> Flags -> IO ()
mergeLCOV paths flags = do
  result <- Merge.mergeLCOVFiles paths
  case result of
    Left err -> reportMergeError err
    Right builder -> writeLCOVOutput flags builder

-- | Write merged Istanbul JSON to the output file or stdout.
writeOutput :: Flags -> Aeson.Value -> IO ()
writeOutput flags merged =
  case flags ^. coverageOutput of
    Just path -> do
      LBS.writeFile path (Aeson.encode merged)
      let pathStr = path
      Print.println [c|  Merged coverage written to {cyan|#{pathStr}}|]
    Nothing -> do
      LBS.putStr (Aeson.encode merged)
      Print.newline

-- | Write merged LCOV to the output file or stdout.
writeLCOVOutput :: Flags -> BB.Builder -> IO ()
writeLCOVOutput flags builder =
  case flags ^. coverageOutput of
    Just path -> do
      LBS.writeFile path (BB.toLazyByteString builder)
      let pathStr = path
      Print.println [c|  Merged LCOV written to {cyan|#{pathStr}}|]
    Nothing ->
      LBS.putStr (BB.toLazyByteString builder)

-- | Report a merge error to stderr.
reportMergeError :: Merge.MergeError -> IO ()
reportMergeError Merge.EmptyInput =
  Print.printErrLn [c|{red|Error:} No input files to merge.|]
reportMergeError (Merge.FileNotFound path) = do
  let pathStr = path
  Print.printErrLn [c|{red|Error:} File not found: #{pathStr}|]
reportMergeError (Merge.ParseError path msg) = do
  let pathStr = path
      msgStr = msg
  Print.printErrLn [c|{red|Error:} Failed to parse #{pathStr}: #{msgStr}|]

-- | Parser for the @--format@ flag.
--
-- @since 0.19.2
formatParser :: Terminal.Parser String
formatParser =
  Terminal.Parser
    { Terminal._singular = "format",
      Terminal._plural = "formats",
      Terminal._parser = parseCovFormat,
      Terminal._suggest = suggestFormats,
      Terminal._examples = exampleFormats
    }

-- | Parse a coverage format argument.
parseCovFormat :: String -> Maybe String
parseCovFormat "istanbul" = Just "istanbul"
parseCovFormat "lcov" = Just "lcov"
parseCovFormat "json" = Just "istanbul"
parseCovFormat _ = Nothing

-- | Suggest format values.
suggestFormats :: String -> IO [String]
suggestFormats _ = pure ["istanbul", "lcov"]

-- | Provide example format values.
exampleFormats :: String -> IO [String]
exampleFormats _ = pure ["istanbul", "lcov"]

-- | Parser for coverage input files (accepts .json and .lcov extensions).
--
-- @since 0.19.2
coverageFileParser :: Terminal.Parser FilePath
coverageFileParser =
  Terminal.Parser
    { Terminal._singular = "coverage file",
      Terminal._plural = "coverage files",
      Terminal._parser = parseCoverageFile,
      Terminal._suggest = \_ -> pure [],
      Terminal._examples = \_ -> pure ["coverage.json", "coverage.lcov"]
    }

-- | Parse a coverage file path.
parseCoverageFile :: String -> Maybe FilePath
parseCoverageFile s
  | null s = Nothing
  | otherwise = Just s

-- | Parser for the @--output@ flag.
--
-- @since 0.19.2
outputParser :: Terminal.Parser String
outputParser =
  Terminal.Parser
    { Terminal._singular = "file",
      Terminal._plural = "files",
      Terminal._parser = parseNonEmpty,
      Terminal._suggest = suggestOutput,
      Terminal._examples = exampleOutput
    }

-- | Parse a non-empty string.
parseNonEmpty :: String -> Maybe String
parseNonEmpty s
  | null s = Nothing
  | otherwise = Just s

-- | Suggest output file paths.
suggestOutput :: String -> IO [String]
suggestOutput _ = pure ["merged-coverage.json", "merged.lcov"]

-- | Provide example output paths.
exampleOutput :: String -> IO [String]
exampleOutput _ = pure ["merged-coverage.json"]
