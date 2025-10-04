{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Command line parsers for Make system options.
--
-- This module provides parsers for command line arguments and options
-- used by the Make system. All parsers follow the Terminal parser
-- framework and provide helpful error messages and suggestions.
--
-- Key parsers:
--   * 'reportType' - Parse error reporting format
--   * 'output' - Parse output file and format
--   * 'docsFile' - Parse documentation output file
--
-- All parsers include:
--   * Clear error messages
--   * Helpful suggestions for invalid input
--   * Example values for user guidance
--
-- @since 0.19.1
module Make.Parser
  ( -- * Parsers
    reportType,
    output,
    docsFile,

    -- * Helper Functions
    parseOutput,
    hasExtension,
    isDevNull,
  )
where

import Make.Types (Output (..), ReportType (..))
import qualified System.FilePath as FilePath
import Terminal (Parser (..))

-- | Parser for error reporting format.
--
-- Currently supports only "json" format for structured error output.
-- Terminal format is used by default when no report type is specified.
--
-- Examples:
--   * "json" → 'Json'
--   * anything else → parse failure with suggestion
reportType :: Parser ReportType
reportType =
  Parser
    { _singular = "report type",
      _plural = "report types",
      _parser = parseReportType,
      _suggest = suggestReportTypes,
      _examples = exampleReportTypes
    }

-- | Parse report type from string.
--
-- Only "json" is currently supported. Returns 'Nothing' for
-- any other input to trigger parser error with suggestions.
parseReportType :: String -> Maybe ReportType
parseReportType "json" = Just Json
parseReportType _ = Nothing

-- | Suggest valid report type values.
--
-- Provides "json" as the only suggestion regardless of input.
-- This helps users discover the available reporting formats.
suggestReportTypes :: String -> IO [String]
suggestReportTypes _ = pure ["json"]

-- | Provide example report type values.
--
-- Returns example values to help users understand valid formats.
-- Used in error messages and help text generation.
exampleReportTypes :: String -> IO [String]
exampleReportTypes _ = pure ["json"]

-- | Parser for output file specification.
--
-- Supports three output formats based on file extension:
--   * ".js" files → JavaScript output
--   * ".html" files → HTML output
--   * "/dev/null" → No output (testing)
--
-- Examples:
--   * "canopy.js" → 'JS "canopy.js"'
--   * "index.html" → 'Html "index.html"'
--   * "/dev/null" → 'DevNull'
output :: Parser Output
output =
  Parser
    { _singular = "output file",
      _plural = "output files",
      _parser = parseOutput,
      _suggest = suggestOutputs,
      _examples = exampleOutputs
    }

-- | Parse output format from file path.
--
-- Determines output format based on file extension and special values:
--   * Files ending in ".html" become HTML output
--   * Files ending in ".js" become JavaScript output
--   * "/dev/null" and variants become DevNull output
--   * Other extensions are rejected
parseOutput :: String -> Maybe Output
parseOutput path
  | isDevNull path = Just DevNull
  | hasExtension ".html" path = Just (Html path)
  | hasExtension ".js" path = Just (JS path)
  | otherwise = Nothing

-- | Suggest valid output file patterns.
--
-- Returns empty list since output files are user-specified paths.
-- The examples function provides better guidance for users.
suggestOutputs :: String -> IO [String]
suggestOutputs _ = pure []

-- | Provide example output file values.
--
-- Shows common patterns for output files to guide users.
-- Includes examples for all supported output formats.
exampleOutputs :: String -> IO [String]
exampleOutputs _ = pure ["canopy.js", "index.html", "/dev/null"]

-- | Parser for documentation output file.
--
-- Validates that the file has a ".json" extension for structured
-- documentation output. Used with the --docs flag.
--
-- Examples:
--   * "docs.json" → "docs.json"
--   * "docs.txt" → parse failure
docsFile :: Parser FilePath
docsFile =
  Parser
    { _singular = "json file",
      _plural = "json files",
      _parser = parseDocsFile,
      _suggest = suggestDocsFiles,
      _examples = exampleDocsFiles
    }

-- | Parse documentation file path.
--
-- Requires ".json" extension for structured documentation output.
-- Returns 'Nothing' if file doesn't have the correct extension.
parseDocsFile :: String -> Maybe FilePath
parseDocsFile path
  | hasExtension ".json" path = Just path
  | otherwise = Nothing

-- | Suggest valid documentation file patterns.
--
-- Returns empty list since docs files are user-specified paths.
-- The examples function provides better guidance.
suggestDocsFiles :: String -> IO [String]
suggestDocsFiles _ = pure []

-- | Provide example documentation file values.
--
-- Shows common patterns for documentation output files.
-- All examples use the required ".json" extension.
exampleDocsFiles :: String -> IO [String]
exampleDocsFiles _ = pure ["docs.json", "documentation.json"]

-- | Check if file path has the specified extension.
--
-- Validates both that the extension matches and that the path
-- is longer than just the extension (prevents ".js" as filename).
--
-- @
-- hasExtension ".js" "canopy.js"  -- True
-- hasExtension ".js" ".js"        -- False (too short)
-- hasExtension ".js" "canopy.ts"  -- False (wrong extension)
-- @
hasExtension :: String -> String -> Bool
hasExtension ext path =
  FilePath.takeExtension path == ext && length path > length ext

-- | Check if path represents null/no output.
--
-- Recognizes common null device paths across different platforms:
--   * "/dev/null" (Unix/Linux)
--   * "NUL" (Windows)
--   * "$null" (PowerShell)
isDevNull :: String -> Bool
isDevNull name =
  name == "/dev/null" || name == "NUL" || name == "$null"
