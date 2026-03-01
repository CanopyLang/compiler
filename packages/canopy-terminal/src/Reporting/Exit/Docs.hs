{-# LANGUAGE OverloadedStrings #-}

-- | Documentation generation error types and reporting.
--
-- @since 0.19.1
module Reporting.Exit.Docs
  ( Docs (..),
    docsToReport,
  )
where

import qualified Exit as BuildExit
import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report,
    appNeedsFileNamesError,
    badDetailsError,
    noOutlineError,
    pkgNeedsExposingError,
    structuredError,
  )

-- | Documentation generation errors.
data Docs
  = DocsNoOutline
  | DocsBadDetails FilePath
  | DocsCannotBuild BuildExit.BuildError
  | DocsAppNeedsFileNames
  | DocsPkgNeedsExposing
  | DocsCannotWrite FilePath String
  deriving (Show)

-- | Convert a 'Docs' error to a structured 'Report'.
docsToReport :: Docs -> Report
docsToReport DocsNoOutline = noOutlineError "canopy docs"
docsToReport (DocsBadDetails path) = badDetailsError path
docsToReport (DocsCannotBuild buildErr) = BuildExit.toDoc buildErr
docsToReport DocsAppNeedsFileNames = appNeedsFileNamesError "canopy docs src/Main.can"
docsToReport DocsPkgNeedsExposing = pkgNeedsExposingError
docsToReport (DocsCannotWrite path msg) = docsCannotWriteError path msg

docsCannotWriteError :: FilePath -> String -> Report
docsCannotWriteError path msg =
  structuredError
    "CANNOT WRITE DOCS"
    (Doc.reflow ("I could not write documentation to " ++ path ++ ": " ++ msg))
    (Doc.reflow "Check that you have write permissions and sufficient disk space.")
