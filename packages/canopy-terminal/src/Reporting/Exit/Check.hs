{-# LANGUAGE OverloadedStrings #-}

-- | Type-check command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Check
  ( Check (..),
    checkToReport,
  )
where

import qualified Exit as BuildExit
import Reporting.Exit.Help
  ( Report,
    appNeedsFileNamesError,
    badDetailsError,
    noOutlineError,
    pkgNeedsExposingError,
  )

-- | Type-check errors (check command).
data Check
  = CheckNoOutline
  | CheckBadDetails FilePath
  | CheckCannotBuild BuildExit.BuildError
  | CheckAppNeedsFileNames
  | CheckPkgNeedsExposing
  deriving (Show)

-- | Convert a 'Check' error to a structured 'Report'.
checkToReport :: Check -> Report
checkToReport CheckNoOutline = noOutlineError "canopy check"
checkToReport (CheckBadDetails path) = badDetailsError path
checkToReport (CheckCannotBuild buildErr) = BuildExit.toDoc buildErr
checkToReport CheckAppNeedsFileNames = appNeedsFileNamesError "canopy check src/Main.can"
checkToReport CheckPkgNeedsExposing = pkgNeedsExposingError
