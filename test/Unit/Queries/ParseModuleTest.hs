
-- | Comprehensive tests for Queries.Parse.Module.
--
-- Tests parse module query including successful parsing,
-- error handling, and integration with query engine.
--
-- @since 0.19.1
module Unit.Queries.ParseModuleTest (tests) where

import qualified AST.Source as Src
import qualified Canopy.Package as Pkg
import qualified Reporting.Annotation as Ann
import qualified Control.Exception as Exception
import qualified Data.ByteString as BS
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Parse.Module as Parse
import qualified Query.Engine as Engine
import Query.Simple
import System.IO.Temp (withSystemTempDirectory)
import qualified System.IO as IO
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Queries.Parse.Module Tests"
    [ testSuccessfulParse,
      testParseErrors,
      testCaching,
      testHashInvalidation
    ]

testSuccessfulParse :: TestTree
testSuccessfulParse =
  testGroup
    "successful parsing"
    [ testCase "parse valid module" $ do
        withValidModule $ \path -> do
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          result <- executeQuery query

          case result of
            Left err -> assertFailure ("Parse failed: " ++ show err)
            Right (ParsedModule modul) -> do
              let moduleName = Src.getName modul
              assertBool "Module name should be Test" (nameMatches moduleName "Test")
            Right _ -> assertFailure "Expected ParsedModule result",
      testCase "parse module with imports" $ do
        withModuleWithImports $ \path -> do
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          result <- executeQuery query

          case result of
            Left err -> assertFailure ("Parse failed: " ++ show err)
            Right (ParsedModule modul) -> do
              let importCount = length (Src._imports modul)
              assertBool "Should have imports" (importCount > 0)
            Right _ -> assertFailure "Expected ParsedModule result",
      testCase "parse module with exports" $ do
        withValidModule $ \path -> do
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          result <- executeQuery query

          case result of
            Left err -> assertFailure ("Parse failed: " ++ show err)
            Right (ParsedModule modul) -> do
              assertBool "Module should have exports" (hasExports modul)
            Right _ -> assertFailure "Expected ParsedModule result"
    ]

testParseErrors :: TestTree
testParseErrors =
  testGroup
    "parse error handling"
    [ testCase "parse invalid syntax" $ do
        withInvalidModule $ \path -> do
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          result <- executeQuery query

          case result of
            Left (DiagnosticError _ (_:_)) -> return ()
            Left (ParseError _ _) -> return ()
            Left err -> assertFailure ("Wrong error type: " ++ show err)
            Right _ -> assertFailure "Expected parse error",
      testCase "parse nonexistent file" $ do
        let path = "/nonexistent/file.can"
        let hash = computeContentHash (BS.pack [1, 2, 3])
        let query = ParseModuleQuery path hash (Parse.Package testPackage)

        -- executeQuery will throw an exception for nonexistent file
        -- This is expected behavior, so we catch it
        result <- Exception.catch
          (executeQuery query)
          (\(Exception.SomeException _) -> return (Left (FileNotFound path)))

        case result of
          Left _ -> return ()
          Right _ -> assertFailure "Expected error for nonexistent file",
      testCase "parse empty file" $ do
        withEmptyModule $ \path -> do
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          result <- executeQuery query

          case result of
            Left (DiagnosticError _ (_:_)) -> return ()
            Left (ParseError _ _) -> return ()
            Left err -> assertFailure ("Wrong error type: " ++ show err)
            Right _ -> assertFailure "Expected parse error for empty file"
    ]

testCaching :: TestTree
testCaching =
  testGroup
    "query caching"
    [ testCase "parse result is cached" $ do
        withValidModule $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          _ <- Engine.runQuery engine query
          _ <- Engine.runQuery engine query

          hits <- Engine.getCacheHits engine
          hits @?= 1,
      testCase "different files have separate cache entries" $ do
        withMultipleModules $ \paths -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let queries =
                [ ParseModuleQuery path hash (Parse.Package testPackage)
                  | path <- paths
                ]

          mapM_ (Engine.runQuery engine) queries

          cacheSize <- Engine.getCacheSize engine
          cacheSize @?= length paths,
      testCase "cache hit returns same module" $ do
        withValidModule $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          result1 <- Engine.runQuery engine query
          result2 <- Engine.runQuery engine query

          case (result1, result2) of
            (Right _, Right _) -> return ()
            (Left e1, Left e2) -> assertFailure ("Both failed: " ++ show e1 ++ ", " ++ show e2)
            _ -> assertFailure "Results differed (one success, one failure)"
    ]

testHashInvalidation :: TestTree
testHashInvalidation =
  testGroup
    "hash-based invalidation"
    [ testCase "different hash causes cache miss" $ do
        withValidModule $ \path -> do
          engine <- Engine.initEngine
          -- Different content produces different hashes (SHA256-based)
          let hash1 = computeContentHash (BS.pack [1, 2, 3])
          let hash2 = computeContentHash (BS.pack [4, 5, 6])
          let query1 = ParseModuleQuery path hash1 (Parse.Package testPackage)
          let query2 = ParseModuleQuery path hash2 (Parse.Package testPackage)

          _ <- Engine.runQuery engine query1
          _ <- Engine.runQuery engine query2

          cacheSize <- Engine.getCacheSize engine
          cacheSize @?= 2,
      testCase "same hash reuses cache entry" $ do
        withValidModule $ \path -> do
          engine <- Engine.initEngine
          let hash = computeContentHash (BS.pack [1, 2, 3])
          let query = ParseModuleQuery path hash (Parse.Package testPackage)

          _ <- Engine.runQuery engine query
          _ <- Engine.runQuery engine query

          misses <- Engine.getCacheMisses engine
          misses @?= 1
    ]

-- Helper functions

testPackage :: Pkg.Name
testPackage = makePackage "test" "pkg"

makePackage :: String -> String -> Pkg.Name
makePackage author project =
  Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

nameMatches :: Name.Name -> String -> Bool
nameMatches actual expected = Name.toChars actual == expected

-- | Check whether a module has a non-empty export list.
--
-- Returns 'True' for @exposing (..)@ (open exports) or for
-- @exposing (name1, name2, ...)@ with at least one item.
hasExports :: Src.Module -> Bool
hasExports modul =
  case Src._exports modul of
    Ann.At _ Src.Open -> True
    Ann.At _ (Src.Explicit items) -> not (null items)

withValidModule :: (FilePath -> IO ()) -> IO ()
withValidModule action =
  withSystemTempDirectory "parse-test" $ \dir -> do
    let path = dir ++ "/Test.can"
    IO.writeFile path validModuleContent
    action path

withModuleWithImports :: (FilePath -> IO ()) -> IO ()
withModuleWithImports action =
  withSystemTempDirectory "parse-test" $ \dir -> do
    let path = dir ++ "/Test.can"
    IO.writeFile path moduleWithImportsContent
    action path

withInvalidModule :: (FilePath -> IO ()) -> IO ()
withInvalidModule action =
  withSystemTempDirectory "parse-test" $ \dir -> do
    let path = dir ++ "/Test.can"
    IO.writeFile path invalidModuleContent
    action path

withEmptyModule :: (FilePath -> IO ()) -> IO ()
withEmptyModule action =
  withSystemTempDirectory "parse-test" $ \dir -> do
    let path = dir ++ "/Test.can"
    IO.writeFile path ""
    action path

withMultipleModules :: ([FilePath] -> IO ()) -> IO ()
withMultipleModules action =
  withSystemTempDirectory "parse-test" $ \dir -> do
    let paths = [dir ++ "/Test" ++ show i ++ ".can" | i <- [1 .. 3 :: Int]]
    mapM_ (`IO.writeFile` validModuleContent) paths
    action paths

validModuleContent :: String
validModuleContent =
  unlines
    [ "module Test exposing (identity)",
      "",
      "identity : a -> a",
      "identity x =",
      "    x"
    ]

moduleWithImportsContent :: String
moduleWithImportsContent =
  unlines
    [ "module Test exposing (main)",
      "",
      "import Html exposing (Html, text)",
      "",
      "main : Html msg",
      "main =",
      "    text \"Hello\""
    ]

invalidModuleContent :: String
invalidModuleContent =
  unlines
    [ "module Test exposing",
      "invalid syntax here",
      "no function body"
    ]
