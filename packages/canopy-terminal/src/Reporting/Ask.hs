{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | User interaction utilities for Terminal.
--
-- Provides functions for asking the user questions and getting responses.
-- Stub implementation for non-critical functionality.
--
-- @since 0.19.1
module Reporting.Ask
  ( ask,
  )
where

-- | Ask user a question (stub - always returns False).
ask :: String -> IO Bool
ask _prompt = pure False
