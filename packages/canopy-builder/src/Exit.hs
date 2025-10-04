{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Pure error types for builder operations.
--
-- Clean, minimal exit codes and error types for the NEW builder.
-- No dependencies on complex OLD reporting system.
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
  )
where

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
