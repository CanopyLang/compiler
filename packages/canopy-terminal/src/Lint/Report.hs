{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Reporting functions for the Canopy lint command.
--
-- Provides terminal (human-readable) and JSON (machine-readable) output
-- formats for lint warnings.  The terminal format uses ANSI colour codes
-- for severity indication, while the JSON format produces a single array
-- of warning objects suitable for editor integration.
--
-- @since 0.19.1
module Lint.Report
  ( -- * Terminal Reporting
    reportTerminal,
    printWarning,
    printFix,
    renderRegion,
    showWord16,

    -- * JSON Reporting
    reportJson,
    encodeWarning,
    encodeRegion,
    encodePosition,

    -- * Summary
    reportExitSummary,

    -- * Name Helpers
    ruleName,
    severityName,
  )
where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Word as Word
import qualified Json.Encode as Encode
import qualified Json.String as JsonString
import Lint.Types
  ( LintFix (..),
    LintRule (..),
    LintWarning (..),
    Severity (..),
  )
import qualified Reporting.Annotation as Ann
import Reporting.Doc.ColorQQ (c)
import qualified System.IO as IO
import qualified Terminal.Print as Print

-- TERMINAL REPORTING

-- | Print all warnings to the terminal in human-readable form.
--
-- Warnings are grouped by rule and printed with their source region and
-- message.  An empty list produces no output (silent success).
reportTerminal :: [LintWarning] -> IO ()
reportTerminal [] = Print.println [c|{green|No lint warnings found.}|]
reportTerminal warnings = mapM_ printWarning warnings

-- | Print a single warning in terminal format, including its severity.
printWarning :: LintWarning -> IO ()
printWarning w = do
  let region = renderRegion (_warnRegion w)
      severity = severityName (_warnSeverity w)
      rule = ruleName (_warnRule w)
      msg = _warnMessage w
      sevColor = case _warnSeverity w of
        SevError -> [c|{red|#{severity}}|]
        SevWarning -> [c|{yellow|#{severity}}|]
        _ -> [c|{cyan|#{severity}}|]
  Print.print [c|{cyan|#{region}} [|]
  Print.print sevColor
  Print.println [c|] [#{rule}]|]
  Print.println [c|  #{msg}|]
  maybe (pure ()) printFix (_warnFix w)

-- | Print the auto-fix hint for a warning.
printFix :: LintFix -> IO ()
printFix (TextReplace orig repl) =
  Print.println [c|  {green|Fix:} replace `#{orig}` with `#{repl}`|]
printFix (RemoveLines start end)
  | start == end = Print.println [c|  {green|Fix:} remove line #{startStr}|]
  | otherwise = Print.println [c|  {green|Fix:} remove lines #{startStr}-#{endStr}|]
  where
    startStr = show start
    endStr = show end

-- | Render a source region as a human-readable @line:col-line:col@ string.
renderRegion :: Ann.Region -> String
renderRegion (Ann.Region (Ann.Position startLine startCol) (Ann.Position endLine endCol)) =
  showWord16 startLine ++ ":" ++ showWord16 startCol
    ++ "-"
    ++ showWord16 endLine ++ ":" ++ showWord16 endCol

-- | Convert a 'Word.Word16' to a decimal string.
showWord16 :: Word.Word16 -> String
showWord16 = show

-- JSON REPORTING

-- | Output all warnings as a JSON array.
reportJson :: [LintWarning] -> IO ()
reportJson warnings =
  LBS.putStr (BB.toLazyByteString (Encode.encode (Encode.list encodeWarning warnings)))
    >> IO.hPutStrLn IO.stdout ""

-- | Encode a single warning as a JSON object, including its severity.
encodeWarning :: LintWarning -> Encode.Value
encodeWarning w =
  Encode.object
    [ (JsonString.fromChars "rule", Encode.string (JsonString.fromChars (ruleName (_warnRule w)))),
      (JsonString.fromChars "severity", Encode.string (JsonString.fromChars (severityName (_warnSeverity w)))),
      (JsonString.fromChars "message", Encode.string (JsonString.fromChars (_warnMessage w))),
      (JsonString.fromChars "region", encodeRegion (_warnRegion w))
    ]

-- | Encode a source region as a JSON object.
encodeRegion :: Ann.Region -> Encode.Value
encodeRegion (Ann.Region (Ann.Position sl sc) (Ann.Position el ec)) =
  Encode.object
    [ (JsonString.fromChars "start", encodePosition sl sc),
      (JsonString.fromChars "end", encodePosition el ec)
    ]

-- | Encode a source position as a JSON object.
encodePosition :: Word.Word16 -> Word.Word16 -> Encode.Value
encodePosition line col =
  Encode.object
    [ (JsonString.fromChars "line", Encode.int (fromIntegral line)),
      (JsonString.fromChars "column", Encode.int (fromIntegral col))
    ]

-- SUMMARY

-- | Print a summary line.
--
-- Only warnings at 'SevError' severity are considered blocking.
-- Info and warning-level issues are reported but do not cause a
-- non-zero exit summary.
reportExitSummary :: [LintWarning] -> IO ()
reportExitSummary [] = pure ()
reportExitSummary warnings =
  Print.println [c|#{summaryText}|]
  where
    total = length warnings
    errors = length (filter (\w -> _warnSeverity w == SevError) warnings)
    summaryText = summaryLine ++ errorSuffix
    summaryLine =
      show total
        ++ " issue"
        ++ (if total == 1 then "" else "s")
        ++ " found"
    errorSuffix
      | errors > 0 =
          " (" ++ show errors ++ " error"
            ++ (if errors == 1 then "" else "s")
            ++ ")."
      | otherwise = "."

-- NAME HELPERS

-- | Return the canonical string name for a lint rule.
ruleName :: LintRule -> String
ruleName UnusedImport = "UnusedImport"
ruleName BooleanCase = "BooleanCase"
ruleName UnnecessaryParens = "UnnecessaryParens"
ruleName DropConcatOfLists = "DropConcatOfLists"
ruleName UseConsOverConcat = "UseConsOverConcat"
ruleName MissingTypeAnnotation = "MissingTypeAnnotation"
ruleName ShadowedVariable = "ShadowedVariable"
ruleName UnusedLetVariable = "UnusedLetVariable"
ruleName PartialFunction = "PartialFunction"
ruleName UnsafeCoerce = "UnsafeCoerce"
ruleName ListAppendInLoop = "ListAppendInLoop"
ruleName UnnecessaryLazyPattern = "UnnecessaryLazyPattern"
ruleName StringConcatInLoop = "StringConcatInLoop"
ruleName TooManyArguments = "TooManyArguments"
ruleName LongFunction = "LongFunction"
ruleName MagicNumber = "MagicNumber"
ruleName InconsistentNaming = "InconsistentNaming"

-- | Return the human-readable name for a severity level.
severityName :: Severity -> String
severityName Off = "off"
severityName SevInfo = "info"
severityName SevWarning = "warning"
severityName SevError = "error"
