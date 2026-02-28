{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | User interface and display formatting for install operations.
--
-- This module handles all user-facing display and interaction during
-- package installation, including change plan formatting, user prompts,
-- and status reporting.
--
-- == Key Features
--
-- * Formatted change plan display with aligned columns
-- * Interactive user prompts for installation confirmation
-- * Status messages and progress reporting
-- * Error message formatting and display
--
-- == Display Architecture
--
-- The display system uses a multi-step process:
--
-- 1. Calculate column widths for alignment
-- 2. Format individual changes into display documents
-- 3. Group changes by type (add, change, remove)
-- 4. Present formatted plan to user for approval
--
-- @since 0.19.1
module Install.Display
  ( -- * Change Plan Display
    createPlanMessage,
    formatChangeDocs,
    calculateWidths,

    -- * User Prompts
    createPromotionMessage,
    promptForApproval,

    -- * Status Messages
    reportAlreadyInstalled,
    reportSuccess,
    reportCancellation,

    -- * Formatting Context
    FormatContext (..),

    -- * Change Formatting
    formatInsert,
    formatChange,
    formatRemove,
    formatPackageName,
  )
where

import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Install.Types
  ( Change (..),
    ChangeDocs (..),
    Widths (..),
    docChanges,
    docInserts,
    docRemoves,
    leftWidth,
    nameWidth,
    rightWidth,
  )
import qualified Reporting.Ask as Ask
import Reporting.Doc (Doc, (<+>))
import qualified Reporting.Doc as Doc
import Reporting.Doc.ColorQQ (c)
import qualified Terminal.Print as Print

-- | Display formatting context for consistent width calculations.
--
-- Groups display parameters together to avoid parameter list violations
-- while maintaining consistent formatting across change displays.
--
-- @since 0.19.1
data FormatContext a = FormatContext
  { _fcToChars :: !(a -> String),
    _fcWidths :: !Widths
  }

-- | Create a formatted change plan message for user review.
--
-- Generates a complete message showing all proposed changes
-- with proper formatting and alignment for user readability.
--
-- ==== Examples
--
-- @
-- Here is my plan:
--
--   Add:
--     elm/http    1.0.0
--     elm/json    1.1.2
--
--   Change:
--     elm/core    1.0.0 => 1.0.2
--
-- Would you like me to update your canopy.json accordingly? [Y/n]:
-- @
--
-- @since 0.19.1
createPlanMessage :: ChangeDocs -> Doc
createPlanMessage changeDocs =
  Doc.vcat
    [ "Here is my plan:",
      formatChangeDocs changeDocs,
      "",
      "Would you like me to update your canopy.json accordingly? [Y/n]: "
    ]

-- | Format change documents into a structured display.
--
-- Organizes changes by type (add, change, remove) and formats
-- them with proper indentation and spacing.
--
-- @since 0.19.1
formatChangeDocs :: ChangeDocs -> Doc
formatChangeDocs changeDocs =
  (Doc.indent 2 . Doc.vcat) . concat $
    [ formatSection "Add:" (changeDocs ^. docInserts),
      formatSection "Change:" (changeDocs ^. docChanges),
      formatSection "Remove:" (changeDocs ^. docRemoves)
    ]

-- | Format a section of changes with a title.
--
-- Creates a titled section only if there are changes to display.
-- Empty sections are omitted from the output.
--
-- @since 0.19.1
formatSection :: String -> [Doc] -> [Doc]
formatSection title entries =
  if null entries
    then []
    else
      [ "",
        Doc.fromChars title,
        Doc.indent 2 (Doc.vcat entries)
      ]

-- | Calculate column widths for aligned change display.
--
-- Analyzes all changes to determine the maximum width needed
-- for each column to ensure proper alignment.
--
-- @since 0.19.1
calculateWidths :: (a -> String) -> Map Pkg.Name (Change a) -> Widths
calculateWidths toChars changeMap =
  Map.foldrWithKey expandWidthsForChange initialWidths changeMap
  where
    initialWidths = Widths 0 0 0
    expandWidthsForChange pkg change widths =
      let ctx = FormatContext toChars widths
       in expandWidths ctx pkg change

-- | Expand column widths based on a single change.
--
-- Updates the running width calculations to accommodate
-- a new change entry.
--
-- @since 0.19.1
expandWidths :: FormatContext a -> Pkg.Name -> Change a -> Widths
expandWidths ctx pkg change =
  let FormatContext toChars widths = ctx
      newName = max (widths ^. nameWidth) (length (Pkg.toChars pkg))
      newCtx = FormatContext toChars widths
   in case change of
        Insert new -> updateWidthsInsert newCtx newName new
        Change old new -> updateWidthsChange newCtx newName old new
        Remove old -> updateWidthsRemove newCtx newName old

-- | Update widths for Insert changes.
updateWidthsInsert :: FormatContext a -> Int -> a -> Widths
updateWidthsInsert ctx newName new =
  let FormatContext toChars widths = ctx
   in Widths newName (max (widths ^. leftWidth) (length (toChars new))) (widths ^. rightWidth)

-- | Update widths for Change modifications.
updateWidthsChange :: FormatContext a -> Int -> a -> a -> Widths
updateWidthsChange ctx newName old new =
  let FormatContext toChars widths = ctx
   in Widths
        newName
        (max (widths ^. leftWidth) (length (toChars old)))
        (max (widths ^. rightWidth) (length (toChars new)))

-- | Update widths for Remove operations.
updateWidthsRemove :: FormatContext a -> Int -> a -> Widths
updateWidthsRemove ctx newName old =
  let FormatContext toChars widths = ctx
   in Widths newName (max (widths ^. leftWidth) (length (toChars old))) (widths ^. rightWidth)

-- | Create a promotion message for moving dependencies.
--
-- Generates user-friendly messages when a package needs to be
-- moved between dependency categories (e.g., test to main deps).
--
-- @since 0.19.1
createPromotionMessage :: String -> String -> Doc
createPromotionMessage fromField toField =
  Doc.vcat
    [ Doc.fillSep (createFoundMessage fromField),
      Doc.fillSep (createMoveMessage toField)
    ]

-- | Create found message for promotion prompts.
createFoundMessage :: String -> [Doc]
createFoundMessage field =
  [ "I",
    "found",
    "it",
    "in",
    "your",
    "canopy.json",
    "file,",
    "but",
    "in",
    "the",
    Doc.dullyellow ("\"" <> Doc.fromChars field <> "\""),
    if field == "test-dependencies" then "field." else "dependencies."
  ]

-- | Create move message for promotion prompts.
createMoveMessage :: String -> [Doc]
createMoveMessage field =
  [ "Should",
    "I",
    "move",
    "it",
    "into",
    Doc.green ("\"" <> Doc.fromChars field <> "\""),
    if field == "dependencies" then "for" else "dependencies",
    "more",
    "general",
    "use?",
    "[Y/n]: "
  ]

-- | Format an insert change for display.
--
-- Creates a formatted line showing a new package addition.
--
-- @since 0.19.1
formatInsert :: FormatContext a -> Pkg.Name -> a -> Doc
formatInsert ctx name new =
  let FormatContext toChars widths = ctx
   in formatPackageName (widths ^. nameWidth) name
        <+> padRight (widths ^. leftWidth) (toChars new)

-- | Format a change modification for display.
--
-- Creates a formatted line showing an old → new version change.
--
-- @since 0.19.1
formatChange :: FormatContext a -> Pkg.Name -> a -> a -> Doc
formatChange ctx name old new =
  let FormatContext toChars widths = ctx
   in Doc.hsep
        [ formatPackageName (widths ^. nameWidth) name,
          padRight (widths ^. leftWidth) (toChars old),
          "=>",
          padRight (widths ^. rightWidth) (toChars new)
        ]

-- | Format a remove change for display.
--
-- Creates a formatted line showing a package removal.
--
-- @since 0.19.1
formatRemove :: FormatContext a -> Pkg.Name -> a -> Doc
formatRemove ctx name old =
  let FormatContext toChars widths = ctx
   in formatPackageName (widths ^. nameWidth) name
        <+> padRight (widths ^. leftWidth) (toChars old)

-- | Format a package name with consistent width.
--
-- Ensures all package names are displayed with the same width
-- for proper column alignment.
--
-- @since 0.19.1
formatPackageName :: Int -> Pkg.Name -> Doc
formatPackageName width name =
  Doc.fill (width + 3) (Doc.fromPackage name)

-- | Pad a string to a specific width with right alignment.
--
-- Adds spaces to the left of the string to achieve the target width.
--
-- @since 0.19.1
padRight :: Int -> String -> Doc
padRight width string =
  Doc.fromChars (replicate (width - length string) ' ') <> Doc.fromChars string

-- | Prompt user for installation approval.
--
-- Presents the change plan and waits for user Y\/N response.
-- Uses 'Reporting.Ask.ask' for interactive terminal input.
--
-- @since 0.19.1
promptForApproval :: Doc -> IO Bool
promptForApproval question =
  Ask.ask (Doc.toString question)

-- | Report that a package is already installed.
--
-- Displays a friendly message when the user tries to install
-- a package that's already present in the project.
--
-- @since 0.19.1
reportAlreadyInstalled :: IO ()
reportAlreadyInstalled = Print.println [c|{green|It is already installed!}|]

-- | Report successful installation completion.
--
-- Displays a success message after installation completes.
--
-- @since 0.19.1
reportSuccess :: IO ()
reportSuccess = Print.println [c|{green|Success!}|]

-- | Report installation cancellation.
--
-- Displays a message when the user cancels the installation.
--
-- @since 0.19.1
reportCancellation :: IO ()
reportCancellation = Print.println [c|Okay, I did not change anything!|]
