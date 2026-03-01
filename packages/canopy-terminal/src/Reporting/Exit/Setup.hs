{-# LANGUAGE OverloadedStrings #-}

-- | Setup, registry, solver, and reactor error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Setup
  ( RegistryProblem (..),
    Solver (..),
    Setup (..),
    setupToReport,
    Reactor (..),
    reactorToReport,
  )
where

import qualified Exit as BuildExit
import Reporting.Diagnostic (Diagnostic)
import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report,
    badDetailsError,
    diagnosticReport,
    structuredError,
  )

-- | Errors related to the package registry.
data RegistryProblem
  = RegistryConnectionError !String
  | RegistryBadData !String
  deriving (Show)

-- | Errors from the dependency solver.
data Solver
  = SolverNoSolution !String
  | SolverConflict !String
  deriving (Show)

-- | Setup (bootstrap) errors.
data Setup
  = SetupRegistryFailed !String
  | SetupCacheFailed !String
  deriving (Show)

-- | Convert a 'Setup' error to a structured 'Report'.
setupToReport :: Setup -> Report
setupToReport (SetupRegistryFailed msg) = setupRegistryFailedError msg
setupToReport (SetupCacheFailed msg) = setupCacheFailedError msg

-- | Errors from the development server (reactor).
data Reactor
  = ReactorCompileError ![Diagnostic]
  | ReactorBuildError ![Diagnostic]
  | ReactorBadDetails !FilePath
  | ReactorBadBuild !BuildExit.BuildError
  | ReactorBadGenerate ![Diagnostic]
  deriving (Show)

-- | Convert a 'Reactor' error to a structured 'Report'.
reactorToReport :: Reactor -> Report
reactorToReport (ReactorCompileError diags) = diagnosticReport "COMPILE ERROR" diags
reactorToReport (ReactorBuildError diags) = diagnosticReport "BUILD ERROR" diags
reactorToReport (ReactorBadDetails path) = badDetailsError path
reactorToReport (ReactorBadBuild buildErr) = BuildExit.toDoc buildErr
reactorToReport (ReactorBadGenerate diags) = diagnosticReport "CODE GENERATION ERROR" diags

setupRegistryFailedError :: String -> Report
setupRegistryFailedError msg =
  structuredError
    "REGISTRY UNAVAILABLE"
    (Doc.reflow ("I could not fetch or read the package registry: " ++ msg))
    (Doc.reflow "Check your internet connection and try again.")

setupCacheFailedError :: String -> Report
setupCacheFailedError msg =
  structuredError
    "CACHE ERROR"
    (Doc.reflow ("The package cache encountered an error: " ++ msg))
    (Doc.reflow "Check disk space and permissions for ~/.canopy/")
