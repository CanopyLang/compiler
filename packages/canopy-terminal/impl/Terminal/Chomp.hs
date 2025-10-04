{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Terminal chomp interface - main orchestration module.
--
-- This module provides the primary interface for the Terminal chomp
-- functionality, coordinating between all specialized sub-modules to
-- provide comprehensive command-line argument and flag parsing.
--
-- @since 0.19.1
module Terminal.Chomp
  ( chomp,
  )
where

import Terminal.Chomp.Processing (processCommandLine)
import Terminal.Chomp.Types (ChompResult)
import Terminal.Internal (Args, Flags)

-- | Main chomp interface for parsing command-line arguments and flags.
--
-- Coordinates the complete parsing workflow including argument processing,
-- flag processing, and suggestion generation. Provides the primary entry
-- point for all Terminal chomp operations.
--
-- ==== Examples
--
-- >>> chomp Nothing ["file.txt"] argSpec flagSpec
-- (suggestions, Right (args, flags))
--
-- >>> chomp (Just 1) ["--help"] argSpec flagSpec
-- (suggestions, Left flagError)
--
-- @since 0.19.1
chomp :: Maybe Int -> [String] -> Args args -> Flags flags -> ChompResult args flags
chomp = processCommandLine
