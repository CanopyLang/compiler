{-# LANGUAGE OverloadedStrings #-}

-- | Core types and data structures for the CLI application.
--
-- This module defines the fundamental types used throughout the command-line
-- interface, providing a clean separation between type definitions and
-- business logic. It supports the modular CLI architecture with well-defined
-- interfaces and reusable components.
--
-- == Key Types
--
-- * Re-exported Terminal framework types
-- * Parser configuration and metadata
-- * Command structure definitions
--
-- == Architecture
--
-- The types in this module support a modular command structure where:
--
-- * Commands are composable and self-contained
-- * Parsers are reusable across different commands
-- * Documentation is structured and consistent
-- * Type safety is maintained throughout the CLI
--
-- @since 0.19.1
module CLI.Types
  ( -- * Terminal Re-exports
    Command,
    Parser,
    (|--),

    -- * Utility Re-exports
    Doc,
  )
where

import Terminal (Command, Parser, (|--))
import Text.PrettyPrint.ANSI.Leijen (Doc)
