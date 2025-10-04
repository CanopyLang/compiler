{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Pure error types for builder operations.
--
-- Clean, minimal exit codes and error types for the NEW builder.
-- Provides beautiful colored error output using the Reporting infrastructure.
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

import qualified Reporting.Doc as D

-- | Build-level errors.
data BuildError
  = BuildCannotCompile CompileError
  | BuildProjectNotFound FilePath
  | BuildInvalidOutline String
  | BuildDependencyError String
  | BuildBadArgs String
  deriving (Show, Eq)

-- | Compilation errors.
data CompileError
  = CompileParseError FilePath String
  | CompileTypeError FilePath String
  | CompileCanonicalizeError FilePath String
  | CompileOptimizeError FilePath String
  | CompileModuleNotFound FilePath
  deriving (Show, Eq)

-- | Make command errors.
data MakeError
  = MakeBuildError String
  | MakeBadGenerate String
  | MakeNoMain
  | MakeMultipleFilesIntoHtml
  deriving (Show, Eq)

-- | Convert error to string for display.
toString :: BuildError -> String
toString err = case err of
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
compileErrorToString err = case err of
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

-- | Convert make error to string.
makeErrorToString :: MakeError -> String
makeErrorToString err = case err of
  MakeBuildError msg ->
    "BUILD ERROR: " ++ msg
  MakeBadGenerate msg ->
    "GENERATE ERROR: " ++ msg
  MakeNoMain ->
    "ERROR: No main function found"
  MakeMultipleFilesIntoHtml ->
    "ERROR: Cannot generate HTML from multiple files"

-- BEAUTIFUL ERROR OUTPUT

-- | Convert error to beautiful colored Doc.
toDoc :: BuildError -> D.Doc
toDoc err = case err of
  BuildCannotCompile compileErr ->
    D.vcat
      [ D.dullred (D.fromChars "-- BUILD ERROR ") <> D.fromChars "----------"
      , D.empty
      , compileErrorToDoc compileErr
      ]
  BuildProjectNotFound path ->
    D.vcat
      [ D.dullred (D.fromChars "-- PROJECT NOT FOUND ") <> D.fromChars "----------"
      , D.empty
      , D.reflow ("I cannot find a project at: " ++ path)
      , D.empty
      , D.reflow
          "Make sure you are running this command from a directory with a \
          \canopy.json or elm.json file."
      ]
  BuildInvalidOutline msg ->
    D.vcat
      [ D.dullred (D.fromChars "-- INVALID PROJECT ") <> D.fromChars "----------"
      , D.empty
      , D.reflow "There is a problem with your project configuration:"
      , D.empty
      , D.indent 4 (D.dullyellow (D.fromChars msg))
      ]
  BuildDependencyError msg ->
    D.vcat
      [ D.dullred (D.fromChars "-- DEPENDENCY ERROR ") <> D.fromChars "----------"
      , D.empty
      , D.reflow msg
      ]
  BuildBadArgs msg ->
    D.vcat
      [ D.dullred (D.fromChars "-- BAD ARGUMENTS ") <> D.fromChars "----------"
      , D.empty
      , D.reflow msg
      ]

-- | Convert compile error to beautiful colored Doc.
compileErrorToDoc :: CompileError -> D.Doc
compileErrorToDoc err = case err of
  CompileParseError path msg ->
    D.vcat
      [ D.reflow ("Parse error in " ++ path ++ ":")
      , D.empty
      , D.indent 4 (D.dullyellow (D.fromChars msg))
      , D.empty
      , D.toSimpleHint
          "Check for missing parentheses, commas, or other syntax issues."
      ]
  CompileTypeError path msg ->
    D.vcat
      [ D.reflow ("Type error in " ++ path ++ ":")
      , D.empty
      , D.indent 4 (D.dullyellow (D.fromChars msg))
      ]
  CompileCanonicalizeError path msg ->
    D.vcat
      [ D.reflow ("Error in " ++ path ++ ":")
      , D.empty
      , D.indent 4 (D.dullyellow (D.fromChars msg))
      ]
  CompileOptimizeError path msg ->
    D.vcat
      [ D.reflow ("Optimization error in " ++ path ++ ":")
      , D.empty
      , D.indent 4 (D.dullyellow (D.fromChars msg))
      ]
  CompileModuleNotFound path ->
    D.vcat
      [ D.reflow "I cannot find a module:"
      , D.empty
      , D.indent 4 (D.dullyellow (D.fromChars path))
      , D.empty
      , D.toSimpleHint
          "Check the \"source-directories\" in your canopy.json or elm.json \
          \to make sure the module is in one of the listed directories."
      ]
