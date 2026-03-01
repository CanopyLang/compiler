{-# LANGUAGE OverloadedStrings #-}

-- | New (project scaffolding) command error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.New
  ( New (..),
    newToReport,
  )
where

import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report,
    fixLine,
    structuredError,
  )

-- | Errors from the @canopy new@ project scaffolding command.
data New
  = -- | Project directory already exists
    NewDirectoryExists !FilePath
  | -- | Project name is empty
    NewEmptyName
  | -- | Project name contains invalid characters
    NewInvalidName !String !String
  | -- | Cannot create project directory
    NewCannotCreateDirectory !FilePath !String
  | -- | Cannot write a project file
    NewCannotWriteFile !FilePath !String
  | -- | Git initialization failed
    NewGitInitFailed !String
  deriving (Show)

-- | Convert a 'New' error to a structured 'Report'.
newToReport :: New -> Report
newToReport (NewDirectoryExists path) = newDirectoryExistsError path
newToReport NewEmptyName = newEmptyNameError
newToReport (NewInvalidName name reason) = newInvalidNameError name reason
newToReport (NewCannotCreateDirectory path msg) = newCannotCreateDirError path msg
newToReport (NewCannotWriteFile path msg) = newCannotWriteFileError path msg
newToReport (NewGitInitFailed msg) = newGitInitFailedError msg

newDirectoryExistsError :: FilePath -> Report
newDirectoryExistsError path =
  structuredError
    "DIRECTORY ALREADY EXISTS"
    (Doc.reflow ("A directory named " ++ path ++ " already exists."))
    ( Doc.vcat
        [ Doc.reflow "Choose a different project name, or remove the existing directory:",
          "",
          fixLine (Doc.green (Doc.fromChars ("rm -rf " ++ path)))
        ]
    )

newEmptyNameError :: Report
newEmptyNameError =
  structuredError
    "MISSING PROJECT NAME"
    (Doc.reflow "You need to provide a project name for canopy new.")
    ( Doc.vcat
        [ Doc.reflow "For example:",
          "",
          fixLine (Doc.green "canopy new my-project")
        ]
    )

newInvalidNameError :: String -> String -> Report
newInvalidNameError name reason =
  structuredError
    "INVALID PROJECT NAME"
    ( Doc.vcat
        [ Doc.reflow ("The project name " ++ show name ++ " is not valid."),
          Doc.reflow reason
        ]
    )
    ( Doc.vcat
        [ Doc.reflow "Project names must:",
          "",
          fixLine (Doc.fromChars "Start with a lowercase letter"),
          fixLine (Doc.fromChars "Contain only lowercase letters, digits, and hyphens"),
          fixLine (Doc.fromChars "Not end with a hyphen"),
          "",
          Doc.reflow "For example:",
          "",
          fixLine (Doc.green "canopy new my-project")
        ]
    )

newCannotCreateDirError :: FilePath -> String -> Report
newCannotCreateDirError path msg =
  structuredError
    "CANNOT CREATE DIRECTORY"
    (Doc.reflow ("I could not create the directory " ++ path ++ ": " ++ msg))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

newCannotWriteFileError :: FilePath -> String -> Report
newCannotWriteFileError path msg =
  structuredError
    "CANNOT WRITE FILE"
    (Doc.reflow ("I could not write the file " ++ path ++ ": " ++ msg))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")

newGitInitFailedError :: String -> Report
newGitInitFailedError msg =
  structuredError
    "GIT INIT FAILED"
    (Doc.reflow ("I could not initialize a git repository: " ++ msg))
    ( Doc.vcat
        [ Doc.reflow "Make sure git is installed, or use the --no-git flag:",
          "",
          fixLine (Doc.green "canopy new my-project --no-git")
        ]
    )
