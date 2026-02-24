{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Pure error types for builder operations.
--
-- Clean, minimal exit codes and error types for the NEW builder.
-- Provides beautiful colored error output using the Reporting infrastructure.
-- 'CompileDiagnosticError' carries structured 'Diagnostic' values from
-- the compiler phases for rich terminal and JSON output.
--
-- @since 0.19.1
module Exit
  ( -- * Build Errors
    BuildError (..)
  , CompileError (..)
  , MakeError (..)

  -- * Conversion
  , toString
  , makeErrorToString
  , toDoc
  , compileErrorToDoc
  )
where

import Reporting.Diagnostic (Diagnostic)
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as D
import qualified Reporting.Error as Error

-- | Build-level errors.
data BuildError
  = BuildCannotCompile CompileError
  | BuildProjectNotFound FilePath
  | BuildInvalidOutline String
  | BuildDependencyError String
  | BuildBadArgs String
  deriving (Show)

-- | Compilation errors.
--
-- 'CompileDiagnosticError' carries structured diagnostics from the
-- compiler phases (parse, canonicalize, type check). These provide
-- error codes, source spans, suggestions, and colored output.
data CompileError
  = CompileParseError FilePath String
  | CompileTypeError FilePath String
  | CompileCanonicalizeError FilePath String
  | CompileOptimizeError FilePath String
  | CompileModuleNotFound FilePath
  | CompileDiagnosticError FilePath [Diagnostic]
  deriving (Show)

-- | Make command errors.
data MakeError
  = MakeBuildError String
  | MakeBadGenerate String
  | MakeNoMain
  | MakeMultipleFilesIntoHtml
  deriving (Show)

-- | Convert error to string for display.
toString :: BuildError -> String
toString = \case
  BuildCannotCompile compileErr ->
    "BUILD ERROR: " ++ compileErrorToString compileErr
  BuildProjectNotFound path ->
    "BUILD ERROR: Project not found at " ++ path
  BuildInvalidOutline msg ->
    "BUILD ERROR: Invalid outline: " ++ msg
  BuildDependencyError msg ->
    "BUILD ERROR: Dependency error: " ++ msg
  BuildBadArgs msg ->
    "BUILD ERROR: Bad arguments: " ++ msg

compileErrorToString :: CompileError -> String
compileErrorToString = \case
  CompileParseError path msg ->
    "Parse error in " ++ path ++ ": " ++ msg
  CompileTypeError path msg ->
    "Type error in " ++ path ++ ": " ++ msg
  CompileCanonicalizeError path msg ->
    "Canonicalization error in " ++ path ++ ": " ++ msg
  CompileOptimizeError path msg ->
    "Optimization error in " ++ path ++ ": " ++ msg
  CompileModuleNotFound path ->
    "Module not found: " ++ path
  CompileDiagnosticError path diags ->
    "Compile error in " ++ path ++ ": " ++ show (length diags) ++ " diagnostic(s)"

-- | Convert make error to string.
makeErrorToString :: MakeError -> String
makeErrorToString = \case
  MakeBuildError msg -> "BUILD ERROR: " ++ msg
  MakeBadGenerate msg -> "GENERATE ERROR: " ++ msg
  MakeNoMain -> "ERROR: No main function found"
  MakeMultipleFilesIntoHtml -> "ERROR: Cannot generate HTML from multiple files"

-- BEAUTIFUL ERROR OUTPUT

-- | Convert error to beautiful colored Doc.
toDoc :: BuildError -> D.Doc
toDoc = \case
  BuildCannotCompile compileErr ->
    compileErrorToDoc compileErr
  BuildProjectNotFound path ->
    structuredError "PROJECT NOT FOUND"
      (D.reflow ("I cannot find a project at: " ++ path))
      (D.reflow "Make sure you are running this command from a directory with a canopy.json or elm.json file.")
  BuildInvalidOutline msg ->
    structuredError "INVALID PROJECT"
      (D.reflow "There is a problem with your project configuration:")
      (D.indent 4 (D.dullyellow (D.fromChars msg)))
  BuildDependencyError msg ->
    structuredErrorNoFix "DEPENDENCY ERROR" (D.reflow msg)
  BuildBadArgs msg ->
    structuredErrorNoFix "BAD ARGUMENTS" (D.reflow msg)

-- | Convert compile error to beautiful colored Doc.
--
-- 'CompileDiagnosticError' renders using the structured diagnostic
-- system with error codes, source snippets, and suggestions.
compileErrorToDoc :: CompileError -> D.Doc
compileErrorToDoc = \case
  CompileParseError path msg ->
    legacyErrorDoc "Parse error" path msg
  CompileTypeError path msg ->
    legacyErrorDoc "Type error" path msg
  CompileCanonicalizeError path msg ->
    legacyErrorDoc "Error" path msg
  CompileOptimizeError path msg ->
    legacyErrorDoc "Optimization error" path msg
  CompileModuleNotFound path ->
    structuredError "MODULE NOT FOUND"
      (D.indent 4 (D.dullyellow (D.fromChars path)))
      (D.toSimpleHint "Check the \"source-directories\" in your canopy.json or elm.json to make sure the module is in one of the listed directories.")
  CompileDiagnosticError path diags ->
    renderDiagnostics path diags

-- | Render structured diagnostics using the Diagnostic rendering system.
--
-- Each diagnostic is rendered with its error code, title bar, message,
-- suggestions, and notes. This produces the same high-quality output
-- as the core compiler's error reporting.
renderDiagnostics :: FilePath -> [Diagnostic] -> D.Doc
renderDiagnostics path diags =
  D.vcat (fmap (renderOneDiagnostic path) (Error.filterCascadeList diags))

-- | Render a single diagnostic.
renderOneDiagnostic :: FilePath -> Diagnostic -> D.Doc
renderOneDiagnostic path diag =
  Diag.diagnosticToDoc path diag

-- | Render a legacy string-based error with colored formatting.
legacyErrorDoc :: String -> FilePath -> String -> D.Doc
legacyErrorDoc label path msg =
  D.vcat
    [ D.reflow (label ++ " in " ++ path ++ ":"),
      "",
      D.indent 4 (D.dullyellow (D.fromChars msg))
    ]

-- | Build a structured error with title bar, explanation, and fix.
structuredError :: String -> D.Doc -> D.Doc -> D.Doc
structuredError title explanation fix =
  D.vcat
    [ errorBar title,
      "",
      explanation,
      "",
      fix,
      ""
    ]

-- | Build a structured error without a fix suggestion.
structuredErrorNoFix :: String -> D.Doc -> D.Doc
structuredErrorNoFix title explanation =
  D.vcat
    [ errorBar title,
      "",
      explanation,
      ""
    ]

-- | Render the colored error title bar.
errorBar :: String -> D.Doc
errorBar title =
  D.dullred ("--" <> " " <> D.fromChars title <> " " <> D.fromChars dashes)
  where
    dashes = replicate (max 1 (80 - 4 - length title)) '-'
