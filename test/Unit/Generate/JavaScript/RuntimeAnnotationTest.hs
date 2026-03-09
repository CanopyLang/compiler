{-# LANGUAGE OverloadedStrings #-}

-- | Validates that every function\/variable in the embedded runtime
-- has a @\@canopy-type@ annotation.
--
-- The Canopy runtime (Runtime.hs, FFIRuntime.hs) embeds raw JavaScript.
-- Every other JS file in the system uses @\@canopy-type@ annotations
-- validated by the FFI pipeline. This test enforces the same standard
-- on the embedded runtime code.
--
-- @since 0.20.0
module Unit.Generate.JavaScript.RuntimeAnnotationTest (tests) where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified Data.List as List
import Test.Tasty
import Test.Tasty.HUnit

import qualified Generate.JavaScript.Runtime as Runtime
import qualified Generate.JavaScript.FFIRuntime as FFIRuntime

tests :: TestTree
tests =
  testGroup
    "Runtime Annotation Coverage"
    [ runtimeAnnotationTests,
      ffiRuntimeAnnotationTests
    ]

-- | Convert a Builder to a list of lines.
builderToLines :: Builder -> [String]
builderToLines =
  map LBS8.unpack . LBS8.lines . BB.toLazyByteString

-- | Extract all function\/var declarations matching the @_Module_name@ pattern.
--
-- Looks for lines starting with @function _@ or @var _@ (after optional whitespace).
findDeclarations :: [String] -> [String]
findDeclarations = concatMap extractDecl
  where
    extractDecl line =
      let trimmed = dropWhile (== ' ') (dropWhile (== '\t') line)
       in case () of
            _
              | "function _" `List.isPrefixOf` trimmed ->
                  [takeWhile (\c -> c /= '(' && c /= ' ') (drop 9 trimmed)]
              | "var _" `List.isPrefixOf` trimmed ->
                  [takeWhile (\c -> c /= ' ' && c /= '=') (drop 4 trimmed)]
              | "async function _" `List.isPrefixOf` trimmed ->
                  [takeWhile (\c -> c /= '(' && c /= ' ') (drop 15 trimmed)]
              | otherwise -> []

-- | Find declarations that lack a preceding @\@canopy-type@ annotation.
--
-- For each declaration, checks whether the previous non-empty line
-- contains @\@canopy-type@.
findUnannotated :: [String] -> [String]
findUnannotated lns = go "" lns
  where
    go _ [] = []
    go prevLine (line : rest) =
      let trimmed = dropWhile (\c -> c == ' ' || c == '\t') line
          decls = extractDeclName trimmed
       in case decls of
            Just name
              | not ("@canopy-type" `List.isInfixOf` prevLine) ->
                  name : go line rest
            _ -> go (if null trimmed then prevLine else line) rest

    extractDeclName trimmed
      | "function _" `List.isPrefixOf` trimmed =
          Just (takeWhile (\c -> c /= '(' && c /= ' ') (drop 9 trimmed))
      | "var _" `List.isPrefixOf` trimmed =
          Just (takeWhile (\c -> c /= ' ' && c /= '=') (drop 4 trimmed))
      | "async function _" `List.isPrefixOf` trimmed =
          Just (takeWhile (\c -> c /= '(' && c /= ' ') (drop 15 trimmed))
      | otherwise = Nothing

-- ── Runtime.hs Tests ──────────────────────────────────────────────

runtimeAnnotationTests :: TestTree
runtimeAnnotationTests =
  testGroup
    "Runtime.hs annotations"
    [ testCase "all runtime declarations have @canopy-type" $
        let lns = builderToLines Runtime.embeddedRuntime
            unannotated = findUnannotated lns
         in unannotated @?= [],
      testCase "runtime has declarations to check" $
        let lns = builderToLines Runtime.embeddedRuntime
            decls = findDeclarations lns
         in assertBool
              ("Expected at least 50 runtime declarations, found " ++ show (length decls))
              (length decls >= 50)
    ]

-- ── FFIRuntime.hs Tests ──────────────────────────────────────────

ffiRuntimeAnnotationTests :: TestTree
ffiRuntimeAnnotationTests =
  testGroup
    "FFIRuntime.hs annotations"
    [ testCase "all $canopy properties have @canopy-type" $
        let lns = builderToLines FFIRuntime.embeddedMarshal
            unannotated = findMissingPropertyAnnotations lns
         in unannotated @?= [],
      testCase "all $validate properties have @canopy-type" $
        let lns = builderToLines FFIRuntime.embeddedValidate
            unannotated = findMissingPropertyAnnotations lns
         in unannotated @?= [],
      testCase "all $smart properties have @canopy-type" $
        let lns = builderToLines FFIRuntime.embeddedSmart
            unannotated = findMissingPropertyAnnotations lns
         in unannotated @?= [],
      testCase "all $env properties have @canopy-type" $
        let lns = builderToLines FFIRuntime.embeddedEnvironment
            unannotated = findMissingPropertyAnnotations lns
         in unannotated @?= []
    ]

-- | Find object properties (inside $canopy, $validate, etc.) missing annotations.
--
-- Properties are lines with exactly 2 spaces of indentation followed by
-- @name: ...@ (the top-level keys of the @var $xxx = { ... }@ objects).
-- Deeper-indented lines are function body code and are ignored.
-- Each property should be preceded by a @\@canopy-type@ comment.
findMissingPropertyAnnotations :: [String] -> [String]
findMissingPropertyAnnotations lns = go "" lns
  where
    go _ [] = []
    go prevLine (line : rest) =
      let propName = extractPropertyName line
       in case propName of
            Just name
              | not ("@canopy-type" `List.isInfixOf` prevLine) ->
                  name : go line rest
            _ -> go (if null (dropWhile (== ' ') line) then prevLine else line) rest

    -- | Only match lines at exactly 2-space indent: "  name: ..."
    extractPropertyName line
      | "  " `List.isPrefixOf` line && not ("   " `List.isPrefixOf` line) =
          let trimmed = drop 2 line
              name = takeWhile (\c -> c /= ':' && c /= ' ') trimmed
           in if ':' `elem` trimmed
                && not (null name)
                && not ("//" `List.isPrefixOf` trimmed)
                && not ("/*" `List.isPrefixOf` trimmed)
                && not ("*" `List.isPrefixOf` trimmed)
                then Just name
                else Nothing
      | otherwise = Nothing
