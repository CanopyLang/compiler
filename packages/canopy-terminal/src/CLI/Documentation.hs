{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Documentation formatting and help text utilities.
--
-- This module provides utilities for creating consistent, well-formatted
-- documentation throughout the CLI application. It handles text reflow,
-- layout composition, and standardized formatting for help text, examples,
-- and command descriptions.
--
-- == Key Functions
--
-- * Text formatting and reflow utilities
-- * Document composition and layout helpers
-- * Standardized help text generation
-- * Welcome and introductory messages
--
-- == Design Principles
--
-- All documentation functions follow these principles:
--
-- * Consistent formatting across all commands
-- * Readable and well-structured help text
-- * Appropriate use of colors and styling
-- * Clear examples and usage instructions
--
-- @since 0.19.1
module CLI.Documentation
  ( -- * Welcome Messages
    createIntroduction,
    createOutro,

    -- * Text Formatting
    stackDocuments,
    reflowText,
  )
where

import qualified Canopy.Version as Version
import qualified Data.List as List
import Text.PrettyPrint.ANSI.Leijen (Doc)
import qualified Text.PrettyPrint.ANSI.Leijen as P

-- | Create the application introduction message.
--
-- Generates a welcoming introduction that displays the Canopy version
-- and provides guidance for new users. The message includes styling
-- and links to getting started resources.
--
-- ==== Examples
--
-- @
-- intro <- createIntroduction
-- print intro  -- Displays formatted welcome message
-- @
--
-- @since 0.19.1
createIntroduction :: Doc
createIntroduction =
  P.vcat
    [ createWelcomeGreeting,
      "",
      createSeparatorLine,
      createGettingStartedInfo,
      createSeparatorLine
    ]

-- | Create the application outro message.
--
-- Generates a friendly closing message that encourages community
-- participation and provides guidance on getting help.
--
-- @since 0.19.1
createOutro :: Doc
createOutro =
  reflowText
    "Be sure to ask on the Canopy slack if you run into trouble! Folks are friendly and\
    \ happy to help out. They hang out there because it is fun, so be kind to get the\
    \ best results!"

-- | Stack multiple documents with spacing.
--
-- Combines a list of documents into a single document with empty lines
-- between each element. This creates well-spaced, readable output.
--
-- ==== Examples
--
-- @
-- let docs = [text "First", text "Second", text "Third"]
-- stackDocuments docs  -- Produces spaced layout
-- @
--
-- @since 0.19.1
stackDocuments :: [Doc] -> Doc
stackDocuments docs =
  P.vcat $ List.intersperse "" docs

-- | Reflow text into a formatted document.
--
-- Takes a string and formats it for display, handling word wrapping
-- and appropriate spacing. This ensures consistent text presentation
-- across all help messages.
--
-- ==== Examples
--
-- @
-- reflowText "This is a long text that will be formatted nicely"
-- -- Produces properly wrapped and spaced text
-- @
--
-- @since 0.19.1
reflowText :: String -> Doc
reflowText text =
  P.fillSep . fmap P.text $ words text

-- | Create the welcome greeting section.
--
-- Internal helper that generates the main greeting with version information.
-- Uses appropriate styling and highlights the Canopy brand.
createWelcomeGreeting :: Doc
createWelcomeGreeting =
  P.fillSep
    [ "Hi,",
      "thank",
      "you",
      "for",
      "trying",
      "out",
      P.green "Canopy",
      P.green (P.text (Version.toChars Version.compiler)) <> ".",
      "I hope you like it!"
    ]

-- | Create a separator line for visual organization.
--
-- Internal helper that generates consistent separator lines used
-- throughout the introduction to organize information visually.
createSeparatorLine :: Doc
createSeparatorLine =
  P.black "-------------------------------------------------------------------------------"

-- | Create the getting started information section.
--
-- Internal helper that provides guidance on how to begin using Canopy,
-- with links to documentation and learning resources.
createGettingStartedInfo :: Doc
createGettingStartedInfo =
  P.vcat
    [ P.black "I highly recommend working through <https://guide.canopy-lang.org> to get started.",
      P.black "It teaches many important concepts, including how to use `canopy` in the terminal."
    ]
