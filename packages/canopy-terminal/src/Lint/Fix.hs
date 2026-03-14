{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Auto-fix logic for the Canopy lint command.
--
-- When the @--fix@ flag is active, fixable lint warnings are applied to the
-- source file in-place.  Line removals are processed bottom-to-top so that
-- line indices remain valid.  Text replacements are applied afterwards since
-- they operate on string content rather than line indices.
--
-- After writing the fixed file, the result is re-parsed to verify that the
-- fix did not introduce syntax errors.  If it did, the original content is
-- restored and a message is printed to stderr.
--
-- @since 0.19.1
module Lint.Fix
  ( -- * Entry Points
    applyFixes,
    applyFixesIfRequested,

    -- * Internal Helpers
    partitionFixes,
    validateFixedFile,
    applyOneFix,
    removeRange,
    replaceFirst,
    replaceFirstStep,
  )
where

import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import Data.Ord (Down (..))
import Lint.Types
  ( Flags (..),
    LintFix (..),
    LintWarning (..),
  )
import qualified Parse.Module as Parse
import Reporting.Doc.ColorQQ (c)
import qualified Terminal.Print as Print

-- | Apply auto-fixes to a file when the @--fix@ flag is active.
--
-- Rewrites the file in-place for each fixable warning, then returns the
-- (now-stale but still informative) original warning list.
applyFixesIfRequested :: Flags -> FilePath -> [LintWarning] -> IO [LintWarning]
applyFixesIfRequested flags path warnings
  | _fix flags = applyFixes path warnings >> pure warnings
  | otherwise = pure warnings

-- | Apply all auto-fixable warnings to a file.
--
-- Line removals are applied bottom-to-top (descending line order) so that
-- earlier line numbers remain valid.  Text replacements are applied
-- afterwards since they operate on string content rather than line indices.
-- After writing the fixed file, the result is re-parsed to verify validity.
applyFixes :: FilePath -> [LintWarning] -> IO ()
applyFixes path warnings = do
  source <- readFile path
  let (lineRemoves, textReplaces) = partitionFixes (Maybe.mapMaybe _warnFix warnings)
      sortedRemoves = List.sortOn (Down . _fixStartLine) lineRemoves
      afterRemoves = foldl applyOneFix source sortedRemoves
      fixed = foldl applyOneFix afterRemoves textReplaces
  writeFile path fixed
  validateFixedFile path source

-- | Partition fixes into line removals and text replacements.
--
-- Line removals must be applied in reverse order to preserve line indices;
-- text replacements are order-independent.
partitionFixes :: [LintFix] -> ([LintFix], [LintFix])
partitionFixes = foldr classify ([], [])
  where
    classify fix@(RemoveLines _ _) (removes, replaces) = (fix : removes, replaces)
    classify fix@(TextReplace _ _) (removes, replaces) = (removes, fix : replaces)

-- | Re-parse the fixed file to verify it is still valid.
--
-- If the fixed file fails to parse, the original content is restored
-- and a message is printed to stderr.
validateFixedFile :: FilePath -> String -> IO ()
validateFixedFile path originalSource = do
  fixedBytes <- BS.readFile path
  case Parse.fromByteString Parse.Application fixedBytes of
    Left _ -> do
      writeFile path originalSource
      Print.println [c|{yellow|Warning:} auto-fix produced invalid syntax in {cyan|#{path}}; reverted.|]
    Right _ -> pure ()

-- | Apply a single fix to source text.
applyOneFix :: String -> LintFix -> String
applyOneFix source (TextReplace original replacement) =
  replaceFirst original replacement source
applyOneFix source (RemoveLines startLine endLine) =
  unlines kept
  where
    allLines = lines source
    kept = removeRange startLine endLine allLines

-- | Remove lines in a 1-indexed inclusive range from a list of lines.
removeRange :: Int -> Int -> [String] -> [String]
removeRange start end lns =
  zipWith keepLine [1 ..] lns >>= id
  where
    keepLine i l
      | i >= start && i <= end = []
      | otherwise = [l]

-- | Replace the first occurrence of @needle@ with @replacement@ in @haystack@.
replaceFirst :: String -> String -> String -> String
replaceFirst needle replacement haystack =
  case List.stripPrefix needle haystack of
    Just rest -> replacement ++ rest
    Nothing -> replaceFirstStep needle replacement haystack

-- | Advance one character and retry the replacement.
replaceFirstStep :: String -> String -> String -> String
replaceFirstStep _ _ [] = []
replaceFirstStep needle replacement (ch : rest) =
  ch : replaceFirst needle replacement rest
