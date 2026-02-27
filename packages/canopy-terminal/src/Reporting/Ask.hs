{-# LANGUAGE OverloadedStrings #-}

-- | User interaction utilities for Terminal.
--
-- Provides functions for asking the user questions and getting Y/N responses.
-- Reads from stdin and writes to stdout. Empty input defaults to 'True' (yes).
--
-- @since 0.19.1
module Reporting.Ask
  ( ask,
  )
where

import qualified System.IO as IO

-- | Ask user a yes\/no question and return the response.
--
-- Prints the prompt followed by " [Y/n] " and reads a line from stdin.
-- Empty input or "y"/"Y" returns 'True'; "n"/"N" returns 'False'.
-- On any other input, re-prompts.
ask :: String -> IO Bool
ask prompt = do
  IO.putStr (prompt ++ " [Y/n] ")
  IO.hFlush IO.stdout
  input <- IO.getLine
  interpretResponse input
  where
    interpretResponse "" = pure True
    interpretResponse "y" = pure True
    interpretResponse "Y" = pure True
    interpretResponse "n" = pure False
    interpretResponse "N" = pure False
    interpretResponse _ = do
      IO.putStrLn "  Please enter y or n."
      ask prompt
