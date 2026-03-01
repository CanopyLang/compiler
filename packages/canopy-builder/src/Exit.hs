{-# LANGUAGE OverloadedStrings #-}

-- | Pure error types for builder operations.
--
-- Clean, minimal exit codes and error types for the NEW builder.
-- Provides beautiful colored error output using the Reporting infrastructure.
-- All compilation errors carry structured 'Diagnostic' values from
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
import qualified Reporting.Doc as Doc
import qualified Reporting.Error as Error

-- | Build-level errors.
data BuildError
  = BuildCannotCompile CompileError
  | BuildMultipleErrors [CompileError]
  | BuildProjectNotFound FilePath
  | BuildInvalidOutline String
  | BuildDependencyError String
  | BuildBadArgs String
  | BuildFileTooLarge FilePath Int Int
  deriving (Show)

-- | Compilation errors.
--
-- 'CompileError' carries structured diagnostics from the compiler
-- phases (parse, canonicalize, type check, optimize). These provide
-- error codes, source spans, suggestions, and colored output.
data CompileError
  = CompileError FilePath [Diagnostic]
  | CompileModuleNotFound FilePath
  | CompileTimeoutError FilePath
  | CompileFileTooLarge FilePath Int Int
  deriving (Show)

-- | Make command errors.
data MakeError
  = MakeBuildError [Diagnostic]
  | MakeBadGenerate [Diagnostic]
  | MakeNoMain
  | MakeMultipleFilesIntoHtml
  deriving (Show)

-- | Convert error to string for display.
toString :: BuildError -> String
toString = \case
  BuildCannotCompile compileErr ->
    "BUILD ERROR: " ++ compileErrorToString compileErr
  BuildMultipleErrors errs ->
    unlines (fmap (\e -> "BUILD ERROR: " ++ compileErrorToString e) errs)
  BuildProjectNotFound path ->
    "BUILD ERROR: Project not found at " ++ path
  BuildInvalidOutline msg ->
    "BUILD ERROR: Invalid outline: " ++ msg
  BuildDependencyError msg ->
    "BUILD ERROR: Dependency error: " ++ msg
  BuildBadArgs msg ->
    "BUILD ERROR: Bad arguments: " ++ msg
  BuildFileTooLarge path actual limit ->
    "BUILD ERROR: File too large: " ++ path
      ++ " (" ++ showMB actual ++ " exceeds " ++ showMB limit ++ " limit)"

compileErrorToString :: CompileError -> String
compileErrorToString = \case
  CompileError path diags ->
    "Compile error in " ++ path ++ ": " ++ show (length diags) ++ " diagnostic(s)"
  CompileModuleNotFound path ->
    "Module not found: " ++ path
  CompileTimeoutError path ->
    "Compilation timed out for " ++ path ++ " (exceeded 5 minute limit)"
  CompileFileTooLarge path actual limit ->
    "File too large: " ++ path
      ++ " (" ++ showMB actual ++ " exceeds " ++ showMB limit ++ " limit)"

-- | Convert make error to string.
makeErrorToString :: MakeError -> String
makeErrorToString = \case
  MakeBuildError diags ->
    "BUILD ERROR: " ++ show (length diags) ++ " diagnostic(s)"
  MakeBadGenerate diags ->
    "GENERATE ERROR: " ++ show (length diags) ++ " diagnostic(s)"
  MakeNoMain -> "ERROR: No main function found"
  MakeMultipleFilesIntoHtml -> "ERROR: Cannot generate HTML from multiple files"

-- BEAUTIFUL ERROR OUTPUT

-- | Convert error to beautiful colored Doc.
toDoc :: BuildError -> Doc.Doc
toDoc = \case
  BuildCannotCompile compileErr ->
    compileErrorToDoc compileErr
  BuildMultipleErrors errs ->
    Doc.vcat (fmap compileErrorToDoc errs)
  BuildProjectNotFound path ->
    structuredError "PROJECT NOT FOUND"
      (Doc.reflow ("I cannot find a project at: " ++ path))
      (Doc.reflow "Make sure you are running this command from a directory with a canopy.json or elm.json file.")
  BuildInvalidOutline msg ->
    structuredError "INVALID PROJECT"
      (Doc.reflow "There is a problem with your project configuration:")
      (Doc.indent 4 (Doc.dullyellow (Doc.fromChars msg)))
  BuildDependencyError msg ->
    structuredErrorNoFix "DEPENDENCY ERROR" (Doc.reflow msg)
  BuildBadArgs msg ->
    structuredErrorNoFix "BAD ARGUMENTS" (Doc.reflow msg)
  BuildFileTooLarge path actual limit ->
    fileTooLargeDoc path actual limit

-- | Convert compile error to beautiful colored Doc.
--
-- All compilation errors render using the structured diagnostic
-- system with error codes, source snippets, and suggestions.
compileErrorToDoc :: CompileError -> Doc.Doc
compileErrorToDoc = \case
  CompileError path diags ->
    renderDiagnostics path diags
  CompileModuleNotFound path ->
    structuredError "MODULE NOT FOUND"
      (Doc.indent 4 (Doc.dullyellow (Doc.fromChars path)))
      (Doc.toSimpleHint "Check the \"source-directories\" in your canopy.json or elm.json to make sure the module is in one of the listed directories.")
  CompileTimeoutError path ->
    structuredError "COMPILATION TIMEOUT"
      (Doc.indent 4 (Doc.dullyellow (Doc.fromChars path)))
      (Doc.toSimpleHint "This module took too long to compile. This can happen with very large modules or pathological type inference. Try splitting the module into smaller parts.")
  CompileFileTooLarge path actual limit ->
    fileTooLargeDoc path actual limit

-- | Render structured diagnostics using the Diagnostic rendering system.
--
-- Each diagnostic is rendered with its error code, title bar, message,
-- suggestions, and notes. This produces the same high-quality output
-- as the core compiler's error reporting.
renderDiagnostics :: FilePath -> [Diagnostic] -> Doc.Doc
renderDiagnostics path diags =
  Doc.vcat (fmap (renderOneDiagnostic path) (Error.filterCascadeList diags))

-- | Render a single diagnostic.
renderOneDiagnostic :: FilePath -> Diagnostic -> Doc.Doc
renderOneDiagnostic path diag =
  Diag.diagnosticToDoc path diag

-- | Build a structured error with title bar, explanation, and fix.
structuredError :: String -> Doc.Doc -> Doc.Doc -> Doc.Doc
structuredError title explanation fix =
  Doc.vcat
    [ errorBar title,
      "",
      explanation,
      "",
      fix,
      ""
    ]

-- | Build a structured error without a fix suggestion.
structuredErrorNoFix :: String -> Doc.Doc -> Doc.Doc
structuredErrorNoFix title explanation =
  Doc.vcat
    [ errorBar title,
      "",
      explanation,
      ""
    ]

-- | Render the colored error title bar.
errorBar :: String -> Doc.Doc
errorBar title =
  Doc.dullred ("--" <> " " <> Doc.fromChars title <> " " <> Doc.fromChars dashes)
  where
    dashes = replicate (max 1 (80 - 4 - length title)) '-'

-- | Format a byte count as a human-readable megabyte string.
--
-- @since 0.19.2
showMB :: Int -> String
showMB bytes =
  show (bytes `div` (1024 * 1024)) ++ " MB"

-- | Render a file-too-large error with a clear suggestion.
--
-- @since 0.19.2
fileTooLargeDoc :: FilePath -> Int -> Int -> Doc.Doc
fileTooLargeDoc path actual limit =
  structuredError "FILE TOO LARGE"
    (Doc.vcat
      [ Doc.indent 4 (Doc.dullyellow (Doc.fromChars path)),
        "",
        Doc.reflow ("This file is " ++ showMB actual
          ++ ", which exceeds the " ++ showMB limit ++ " limit.")
      ])
    (Doc.reflow "Consider splitting it into smaller modules.")
