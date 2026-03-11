{-# LANGUAGE OverloadedStrings #-}

-- | Kit command error types and reporting.
--
-- Provides structured error types for all failure modes in the Kit framework
-- commands (scaffolding, dev server, production build) and converts each
-- to a human-readable 'Report' with fix suggestions.
--
-- @since 0.19.2
module Reporting.Exit.Kit
  ( Kit (..)
  , kitToReport
  ) where

import Reporting.Doc ((<+>))
import qualified Reporting.Doc as Doc
import Reporting.Exit.Help
  ( Report
  , fixLine
  , noOutlineError
  , structuredError
  , structuredErrorNoFix
  )

-- | Errors that can occur during Kit operations.
--
-- @since 0.19.2
data Kit
  = KitNoOutline
    -- ^ No @canopy.json@ found in the project directory.
  | KitNotKitProject
    -- ^ The project exists but is not configured as a Kit project.
  | KitRouteScanError !String
    -- ^ Route scanning failed with the given reason.
  | KitRouteValidationError !String
    -- ^ Route validation found a conflict or error.
  | KitBuildError !String
    -- ^ A build step failed.
  | KitScaffoldError !String
    -- ^ Project scaffolding could not complete.
  | KitViteError !String
    -- ^ Vite process exited with an error.
  deriving (Show)

-- | Convert a 'Kit' error to a structured 'Report'.
--
-- @since 0.19.2
kitToReport :: Kit -> Report
kitToReport KitNoOutline = noOutlineError "canopy kit-dev"
kitToReport KitNotKitProject = notKitProjectError
kitToReport (KitRouteScanError reason) = routeScanError reason
kitToReport (KitRouteValidationError reason) = routeValidationError reason
kitToReport (KitBuildError reason) = buildError reason
kitToReport (KitScaffoldError reason) = scaffoldError reason
kitToReport (KitViteError reason) = viteError reason

-- | Error when the project is not a Kit project.
notKitProjectError :: Report
notKitProjectError =
  structuredError
    "NOT A KIT PROJECT"
    (Doc.reflow "This project does not appear to be a Kit project. Kit projects require a routes directory at src/routes/.")
    ( Doc.vcat
        [ Doc.reflow "To create a new Kit project, run:"
        , ""
        , fixLine (Doc.green "canopy kit-new my-app")
        ]
    )

-- | Error when route scanning fails.
routeScanError :: String -> Report
routeScanError reason =
  structuredError
    "ROUTE SCAN ERROR"
    (Doc.reflow ("I ran into a problem while scanning your routes directory: " ++ reason))
    ( Doc.vcat
        [ Doc.reflow "Make sure your src/routes/ directory exists and contains valid page.can files."
        , ""
        , fixLine (Doc.green "ls src/routes/")
        ]
    )

-- | Error when route validation finds conflicts.
routeValidationError :: String -> Report
routeValidationError reason =
  structuredErrorNoFix
    "ROUTE VALIDATION ERROR"
    (Doc.reflow ("I found a problem with your routes: " ++ reason))

-- | Error when a build step fails.
buildError :: String -> Report
buildError reason =
  structuredError
    "KIT BUILD ERROR"
    (Doc.reflow ("The build failed: " ++ reason))
    ( Doc.vcat
        [ Doc.reflow "Try running the individual steps to isolate the problem:"
        , ""
        , fixLine (Doc.green "canopy make --optimize" <+> Doc.reflow "to check Canopy compilation")
        , fixLine (Doc.green "npx vite build" <+> Doc.reflow "to check Vite bundling")
        ]
    )

-- | Error when scaffolding cannot complete.
scaffoldError :: String -> Report
scaffoldError reason =
  structuredError
    "SCAFFOLD ERROR"
    (Doc.reflow ("I could not create the project: " ++ reason))
    (Doc.reflow "Check that the target directory does not already exist and that you have write permissions.")

-- | Error when the Vite process fails.
viteError :: String -> Report
viteError reason =
  structuredError
    "VITE ERROR"
    (Doc.reflow ("The Vite process failed: " ++ reason))
    ( Doc.vcat
        [ Doc.reflow "Make sure Vite is installed:"
        , ""
        , fixLine (Doc.green "npm install")
        , ""
        , Doc.reflow "Then try again."
        ]
    )
