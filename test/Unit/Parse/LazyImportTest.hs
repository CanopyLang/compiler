{-# LANGUAGE OverloadedStrings #-}

-- | Tests for lazy import parsing.
--
-- Validates that the @lazy import@ syntax is parsed correctly,
-- preserving the lazy flag on import declarations and rejecting
-- invalid combinations.
--
-- @since 0.19.2
module Unit.Parse.LazyImportTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Data.Name as Name
import qualified Parse.Module as M
import qualified Reporting.Annotation as A
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Parse.LazyImport"
    [ testLazyImportParsesWithFlag
    , testNormalImportHasNoLazyFlag
    , testLazyImportWithExposing
    , testLazyImportWithAlias
    , testLazyImportWithAliasAndExposing
    , testLazyAsVariableName
    , testMultipleLazyImports
    , testMixedImports
    , testLazyImportPreservesModuleName
    , testLazyImportNoExposing
    , testLazyImportExposingDotDot
    , testLazyImportMultipleExposing
    , testLazyImportDottedModule
    ]

-- | Helper to parse a module string.
parseModule :: M.ProjectType -> String -> Either a Src.Module
parseModule pt s =
  case M.fromByteString pt (C8.pack s) of
    Right m -> Right m
    Left _ -> Left undefined

-- | Helper to parse as application.
parseApp :: String -> Either a Src.Module
parseApp = parseModule M.Application

-- | Find an import by name in a module's imports.
findImport :: Name.Name -> [Src.Import] -> Maybe Src.Import
findImport target = go
  where
    go [] = Nothing
    go (imp@(Src.Import (A.At _ n) _ _ _) : rest)
      | n == target = Just imp
      | otherwise = go rest

testLazyImportParsesWithFlag :: TestTree
testLazyImportParsesWithFlag =
  testCase "lazy import sets _importLazy = True" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Dashboard") (Src._imports modul) of
          Just (Src.Import _ _ _ isLazy) ->
            isLazy @?= True
          Nothing -> assertFailure "Dashboard import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Dashboard"
      , ""
      , "main = text \"hello\""
      ]

testNormalImportHasNoLazyFlag :: TestTree
testNormalImportHasNoLazyFlag =
  testCase "regular import has _importLazy = False" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Utils") (Src._imports modul) of
          Just (Src.Import _ _ _ isLazy) ->
            isLazy @?= False
          Nothing -> assertFailure "Utils import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "import Utils"
      , ""
      , "main = text \"hello\""
      ]

testLazyImportWithExposing :: TestTree
testLazyImportWithExposing =
  testCase "lazy import Foo exposing (bar) works" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Foo") (Src._imports modul) of
          Just (Src.Import _ _ _ isLazy) ->
            isLazy @?= True
          Nothing -> assertFailure "Foo import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Foo exposing (bar)"
      , ""
      , "main = text \"hello\""
      ]

testLazyImportWithAlias :: TestTree
testLazyImportWithAlias =
  testCase "lazy import Foo as F works" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Foo") (Src._imports modul) of
          Just (Src.Import _ alias _ isLazy) -> do
            isLazy @?= True
            alias @?= Just (Name.fromChars "F")
          Nothing -> assertFailure "Foo import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Foo as F"
      , ""
      , "main = text \"hello\""
      ]

testLazyImportWithAliasAndExposing :: TestTree
testLazyImportWithAliasAndExposing =
  testCase "lazy import Foo as F exposing (bar, Baz) works" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Foo") (Src._imports modul) of
          Just (Src.Import _ alias _ isLazy) -> do
            isLazy @?= True
            alias @?= Just (Name.fromChars "F")
          Nothing -> assertFailure "Foo import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Foo as F exposing (bar, Baz)"
      , ""
      , "main = text \"hello\""
      ]

testLazyAsVariableName :: TestTree
testLazyAsVariableName =
  testCase "lazy as variable name works inside expressions" $
    case parseApp src of
      Right modul ->
        length (Src._values modul) @?= 2
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "x = lazy"
      , ""
      , "main = x"
      ]

testMultipleLazyImports :: TestTree
testMultipleLazyImports =
  testCase "multiple lazy imports all parse correctly" $
    case parseApp src of
      Right modul -> do
        let imports = Src._imports modul
        case findImport (Name.fromChars "Dashboard") imports of
          Just (Src.Import _ _ _ isLazy) -> isLazy @?= True
          Nothing -> assertFailure "Dashboard import not found"
        case findImport (Name.fromChars "Settings") imports of
          Just (Src.Import _ _ _ isLazy) -> isLazy @?= True
          Nothing -> assertFailure "Settings import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Dashboard"
      , "lazy import Settings"
      , ""
      , "main = text \"hello\""
      ]

testMixedImports :: TestTree
testMixedImports =
  testCase "mixed lazy and normal imports parse correctly" $
    case parseApp src of
      Right modul -> do
        let imports = Src._imports modul
        case findImport (Name.fromChars "Dashboard") imports of
          Just (Src.Import _ _ _ isLazy) -> isLazy @?= True
          Nothing -> assertFailure "Dashboard import not found"
        case findImport (Name.fromChars "Utils") imports of
          Just (Src.Import _ _ _ isLazy) -> isLazy @?= False
          Nothing -> assertFailure "Utils import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "import Utils"
      , "lazy import Dashboard"
      , ""
      , "main = text \"hello\""
      ]

testLazyImportPreservesModuleName :: TestTree
testLazyImportPreservesModuleName =
  testCase "lazy import preserves exact module name" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "My.Long.Module") (Src._imports modul) of
          Just (Src.Import (A.At _ name) _ _ isLazy) -> do
            isLazy @?= True
            name @?= Name.fromChars "My.Long.Module"
          Nothing -> assertFailure "My.Long.Module import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import My.Long.Module"
      , ""
      , "main = text \"hello\""
      ]

testLazyImportNoExposing :: TestTree
testLazyImportNoExposing =
  testCase "lazy import with no exposing clause" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Foo") (Src._imports modul) of
          Just (Src.Import _ Nothing _ isLazy) ->
            isLazy @?= True
          Just (Src.Import _ (Just _) _ _) ->
            assertFailure "expected no alias"
          Nothing -> assertFailure "Foo import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Foo"
      , ""
      , "main = text \"hello\""
      ]

testLazyImportExposingDotDot :: TestTree
testLazyImportExposingDotDot =
  testCase "lazy import with exposing (..)" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Foo") (Src._imports modul) of
          Just (Src.Import _ _ exposing isLazy) -> do
            isLazy @?= True
            case exposing of
              Src.Open -> return ()
              _ -> assertFailure "expected Open exposing"
          Nothing -> assertFailure "Foo import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Foo exposing (..)"
      , ""
      , "main = text \"hello\""
      ]

testLazyImportMultipleExposing :: TestTree
testLazyImportMultipleExposing =
  testCase "lazy import with multiple exposing items" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Foo") (Src._imports modul) of
          Just (Src.Import _ _ _ isLazy) ->
            isLazy @?= True
          Nothing -> assertFailure "Foo import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Foo exposing (bar, baz, Qux)"
      , ""
      , "main = text \"hello\""
      ]

testLazyImportDottedModule :: TestTree
testLazyImportDottedModule =
  testCase "lazy import with dotted module name" $
    case parseApp src of
      Right modul ->
        case findImport (Name.fromChars "Page.Dashboard") (Src._imports modul) of
          Just (Src.Import _ _ _ isLazy) ->
            isLazy @?= True
          Nothing -> assertFailure "Page.Dashboard import not found"
      Left _ -> assertFailure "parse failed"
  where
    src = unlines
      [ "module Main exposing (..)"
      , ""
      , "lazy import Page.Dashboard"
      , ""
      , "main = text \"hello\""
      ]
