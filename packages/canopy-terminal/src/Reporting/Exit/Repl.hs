{-# LANGUAGE OverloadedStrings #-}

-- | REPL command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Repl
  ( Repl (..),
    replToReport,
  )
where

import qualified Exit as BuildExit
import Reporting.Diagnostic (Diagnostic)
import Reporting.Exit.Help
  ( Report,
    badDetailsError,
    diagnosticReport,
  )

-- | REPL errors.
data Repl
  = ReplBadDetails FilePath
  | ReplBadGenerate [Diagnostic]
  | ReplCannotBuild BuildExit.BuildError
  deriving (Show)

-- | Convert a 'Repl' error to a structured 'Report'.
replToReport :: Repl -> Report
replToReport (ReplBadDetails path) = badDetailsError path
replToReport (ReplBadGenerate diags) = diagnosticReport "CODE GENERATION ERROR" diags
replToReport (ReplCannotBuild buildErr) = BuildExit.toDoc buildErr
