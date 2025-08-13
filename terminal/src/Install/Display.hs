{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

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
    
    -- * Change Formatting
    formatInsert,
    formatChange,
    formatRemove,
    formatPackageName,
  ) where

import Control.Lens ((^.))
import qualified Canopy.Package as Pkg
import Data.Map (Map)
import qualified Data.Map as Map
import Install.Types 
  ( Change (..)
  , ChangeDocs (..)
  , Widths (..)
  , docInserts
  , docChanges
  , docRemoves
  , nameWidth
  , leftWidth
  , rightWidth
  )
import Reporting.Doc (Doc, (<+>))
import qualified Reporting.Doc as D

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
  D.vcat
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
  (D.indent 2 . D.vcat) . concat $
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
        D.fromChars title,
        D.indent 2 (D.vcat entries)
      ]

-- | Calculate column widths for aligned change display.
--
-- Analyzes all changes to determine the maximum width needed
-- for each column to ensure proper alignment.
--
-- @since 0.19.1
calculateWidths :: (a -> String) -> Map Pkg.Name (Change a) -> Widths
calculateWidths toChars changeMap = 
  Map.foldrWithKey (expandWidths toChars) initialWidths changeMap
  where
    initialWidths = Widths 0 0 0

-- | Expand column widths based on a single change.
--
-- Updates the running width calculations to accommodate
-- a new change entry.
--
-- @since 0.19.1
expandWidths :: (a -> String) -> Pkg.Name -> Change a -> Widths -> Widths
expandWidths toChars pkg change widths =
  let nameLen = length (Pkg.toChars pkg)
      currentName = widths ^. nameWidth
      currentLeft = widths ^. leftWidth  
      currentRight = widths ^. rightWidth
      
      newName = max currentName nameLen
  in case change of
       Insert new ->
         Widths newName (max currentLeft (length (toChars new))) currentRight
       Change old new ->
         Widths newName 
                (max currentLeft (length (toChars old))) 
                (max currentRight (length (toChars new)))
       Remove old ->
         Widths newName (max currentLeft (length (toChars old))) currentRight

-- | Create a promotion message for moving dependencies.
--
-- Generates user-friendly messages when a package needs to be
-- moved between dependency categories (e.g., test to main deps).
--
-- @since 0.19.1
createPromotionMessage :: String -> String -> Doc
createPromotionMessage fromField toField =
  D.vcat
    [ D.fillSep (foundInMessage fromField),
      D.fillSep (moveToMessage toField)
    ]
  where
    foundInMessage field =
      ["I", "found", "it", "in", "your", "canopy.json", "file,", "but", "in", "the", 
       D.dullyellow ("\"" <> D.fromChars field <> "\""), 
       if field == "test-dependencies" then "field." else "dependencies."]
    moveToMessage field =
      ["Should", "I", "move", "it", "into", 
       D.green ("\"" <> D.fromChars field <> "\""), 
       if field == "dependencies" then "for" else "dependencies", 
       "more", "general", "use?", "[Y/n]: "]

-- | Format an insert change for display.
--
-- Creates a formatted line showing a new package addition.
--
-- @since 0.19.1
formatInsert :: (a -> String) -> Widths -> Pkg.Name -> a -> Doc
formatInsert toChars widths name new =
  formatPackageName (widths ^. nameWidth) name <+> 
  padRight (widths ^. leftWidth) (toChars new)

-- | Format a change modification for display.
--
-- Creates a formatted line showing an old → new version change.
--
-- @since 0.19.1
formatChange :: (a -> String) -> Widths -> Pkg.Name -> a -> a -> Doc
formatChange toChars widths name old new =
  D.hsep
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
formatRemove :: (a -> String) -> Widths -> Pkg.Name -> a -> Doc
formatRemove toChars widths name old =
  formatPackageName (widths ^. nameWidth) name <+> 
  padRight (widths ^. leftWidth) (toChars old)

-- | Format a package name with consistent width.
--
-- Ensures all package names are displayed with the same width
-- for proper column alignment.
--
-- @since 0.19.1
formatPackageName :: Int -> Pkg.Name -> Doc
formatPackageName width name =
  D.fill (width + 3) (D.fromPackage name)

-- | Pad a string to a specific width with right alignment.
--
-- Adds spaces to the left of the string to achieve the target width.
--
-- @since 0.19.1
padRight :: Int -> String -> Doc
padRight width string =
  D.fromChars (replicate (width - length string) ' ') <> D.fromChars string

-- | Prompt user for installation approval.
--
-- Presents a formatted question and waits for user response.
-- This is a placeholder - actual implementation would use Reporting.ask.
--
-- @since 0.19.1
promptForApproval :: Doc -> IO Bool
promptForApproval _question = do
  -- TODO: Implement actual user prompting
  -- return Reporting.ask question
  pure True

-- | Report that a package is already installed.
--
-- Displays a friendly message when the user tries to install
-- a package that's already present in the project.
--
-- @since 0.19.1
reportAlreadyInstalled :: IO ()
reportAlreadyInstalled = putStrLn "It is already installed!"

-- | Report successful installation completion.
--
-- Displays a success message after installation completes.
--
-- @since 0.19.1
reportSuccess :: IO ()
reportSuccess = putStrLn "Success!"

-- | Report installation cancellation.
--
-- Displays a message when the user cancels the installation.
--
-- @since 0.19.1
reportCancellation :: IO ()
reportCancellation = putStrLn "Okay, I did not change anything!"