{-# LANGUAGE OverloadedStrings #-}

-- | Init command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Init
  ( Init (..),
    initToReport,
  )
where

import qualified Data.List as List
import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report,
    badDetailsError,
    fixLine,
    structuredError,
  )

-- | Init (project initialization) errors.
data Init
  = InitAlreadyExists
  | InitRegistryProblem String
  | InitSolverProblem String
  | InitNoSolution [String]
  | InitNoOfflineSolution [String]
  | InitCannotCreateDirectory FilePath
  | InitCannotWriteFile FilePath
  | InitBadDetails FilePath
  deriving (Show)

-- | Convert an 'Init' error to a structured 'Report'.
initToReport :: Init -> Report
initToReport InitAlreadyExists = initAlreadyExistsError
initToReport (InitRegistryProblem msg) = initRegistryProblemError msg
initToReport (InitSolverProblem msg) = initSolverProblemError msg
initToReport (InitNoSolution pkgs) = initNoSolutionError pkgs
initToReport (InitNoOfflineSolution pkgs) = initNoOfflineSolutionError pkgs
initToReport (InitCannotCreateDirectory path) = initCannotCreateDirError path
initToReport (InitCannotWriteFile path) = initCannotWriteFileError path
initToReport (InitBadDetails path) = badDetailsError path

initAlreadyExistsError :: Report
initAlreadyExistsError =
  structuredError
    "PROJECT ALREADY EXISTS"
    (Doc.reflow "There is already a canopy.json in this directory.")
    (Doc.reflow "Use a different directory, or delete the existing canopy.json to start over.")

initRegistryProblemError :: String -> Report
initRegistryProblemError msg =
  structuredError
    "REGISTRY ERROR"
    (Doc.reflow ("I could not access the package registry during project initialization: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Check your internet connection, or try:",
          "",
          fixLine (Doc.green "canopy setup")
        ]
    )

initSolverProblemError :: String -> Report
initSolverProblemError msg =
  structuredError
    "SOLVER ERROR"
    (Doc.reflow ("The dependency solver encountered a problem: " ++ msg))
    (Doc.reflow "This may be a temporary registry issue. Try again in a moment.")

initNoSolutionError :: [String] -> Report
initNoSolutionError pkgs =
  structuredError
    "NO DEPENDENCY SOLUTION"
    ( Doc.vcat
        [ Doc.reflow "I could not find a set of package versions that work together.",
          Doc.reflow ("Packages involved: " ++ List.intercalate ", " pkgs)
        ]
    )
    (Doc.reflow "This is unusual for a new project. Try running canopy setup first.")

initNoOfflineSolutionError :: [String] -> Report
initNoOfflineSolutionError pkgs =
  structuredError
    "NO OFFLINE SOLUTION"
    ( Doc.vcat
        [ Doc.reflow "I could not find cached package versions that work together.",
          Doc.reflow ("Packages involved: " ++ List.intercalate ", " pkgs)
        ]
    )
    ( Doc.vcat
        [ Doc.reflow "Connect to the internet and try again, or run:",
          "",
          fixLine (Doc.green "canopy setup")
        ]
    )

initCannotCreateDirError :: FilePath -> Report
initCannotCreateDirError path =
  structuredError
    "CANNOT CREATE DIRECTORY"
    (Doc.reflow ("I could not create the directory: " ++ path))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

initCannotWriteFileError :: FilePath -> Report
initCannotWriteFileError path =
  structuredError
    "CANNOT WRITE FILE"
    (Doc.reflow ("I could not write the file: " ++ path))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")
