{-# LANGUAGE OverloadedStrings #-}

-- | Tests for canopy.json format improvements.
--
-- Verifies that the new optional fields (@\"scripts\"@ and @\"repository\"@)
-- are correctly parsed from JSON, and that backward compatibility with
-- elm.json is maintained.
--
-- Note: The 'ToJSON' and 'FromJSON' instances for 'AppOutline' use
-- different JSON structures (ToJSON flattens deps, FromJSON reads nested
-- direct\/indirect), so full round-trip testing requires using the decode
-- format for both directions.
--
-- @since 0.19.2
module Unit.OutlineFormatTest (tests) where

import qualified Canopy.Outline as Outline
import qualified Data.Aeson as Json
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.Map.Strict as Map
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Canopy.Outline Format"
    [ backwardCompatTests,
      scriptsParsingTests,
      repositoryParsingTests,
      pkgParsingTests
    ]

-- BACKWARD COMPATIBILITY

backwardCompatTests :: TestTree
backwardCompatTests =
  Test.testGroup
    "Backward compatibility"
    [ Test.testCase "elm-version field is accepted" $
        decodeSucceeds appJsonWithElmVersion,
      Test.testCase "canopy-version field is accepted" $
        decodeSucceeds appJsonMinimal,
      Test.testCase "missing scripts field defaults to Nothing" $
        decodeAppField appJsonMinimal Outline._appScripts Nothing,
      Test.testCase "missing repository field defaults to Nothing" $
        decodeAppField appJsonMinimal Outline._appRepository Nothing,
      Test.testCase "source-directories are parsed" $
        decodeAppField appJsonMinimal Outline._appSrcDirs [Outline.RelativeSrcDir "src"],
      Test.testCase "canopy version is parsed" $
        decodeAppCheck appJsonMinimal $ \app ->
          Outline._appCanopy app @?= Outline._appCanopy app
    ]

-- SCRIPTS PARSING

scriptsParsingTests :: TestTree
scriptsParsingTests =
  Test.testGroup
    "Scripts field parsing"
    [ Test.testCase "scripts field is parsed" $
        decodeAppField
          appJsonWithScripts
          Outline._appScripts
          (Just (Map.fromList [("prebuild", "echo hello"), ("postbuild", "echo done")])),
      Test.testCase "empty scripts object is parsed" $
        decodeAppField
          appJsonWithEmptyScripts
          Outline._appScripts
          (Just Map.empty),
      Test.testCase "scripts field absent yields Nothing" $
        decodeAppField
          appJsonMinimal
          Outline._appScripts
          Nothing,
      Test.testCase "scripts with multiple entries" $
        decodeAppCheck appJsonWithScripts $ \app ->
          case Outline._appScripts app of
            Just scripts -> Map.size scripts @?= 2
            Nothing -> Test.assertFailure "Expected scripts field"
    ]

-- REPOSITORY PARSING

repositoryParsingTests :: TestTree
repositoryParsingTests =
  Test.testGroup
    "Repository field parsing"
    [ Test.testCase "repository field is parsed" $
        decodeAppField
          appJsonWithRepo
          Outline._appRepository
          (Just "https://github.com/example/project"),
      Test.testCase "repository field absent yields Nothing" $
        decodeAppField
          appJsonMinimal
          Outline._appRepository
          Nothing,
      Test.testCase "both scripts and repository can be present" $
        decodeAppCheck appJsonWithBothOptional $ \app -> do
          Test.assertBool "scripts should be present" (Outline._appScripts app /= Nothing)
          Test.assertBool "repository should be present" (Outline._appRepository app /= Nothing)
    ]

-- PACKAGE OUTLINE TESTS

pkgParsingTests :: TestTree
pkgParsingTests =
  Test.testGroup
    "Package outline parsing"
    [ Test.testCase "package outline decodes" $
        decodePkgSucceeds pkgJsonMinimal,
      Test.testCase "package name is parsed" $
        decodePkgCheck pkgJsonMinimal $ \pkg ->
          show (Outline._pkgName pkg) @?= "Name {_author = author, _project = project}"
    ]

-- HELPERS

-- | Decode JSON and assert success.
decodeSucceeds :: BL8.ByteString -> Test.Assertion
decodeSucceeds json =
  case Json.eitherDecode json :: Either String Outline.Outline of
    Right _ -> pure ()
    Left err -> Test.assertFailure ("JSON decode failed: " ++ err)

-- | Decode JSON as App and check a specific field.
decodeAppField :: (Eq a, Show a) => BL8.ByteString -> (Outline.AppOutline -> a) -> a -> Test.Assertion
decodeAppField json accessor expected =
  case Json.eitherDecode json :: Either String Outline.Outline of
    Right (Outline.App app) -> accessor app @?= expected
    Right other -> Test.assertFailure ("Expected App, got: " ++ show other)
    Left err -> Test.assertFailure ("JSON decode failed: " ++ err)

-- | Decode JSON as App and run a custom assertion.
decodeAppCheck :: BL8.ByteString -> (Outline.AppOutline -> Test.Assertion) -> Test.Assertion
decodeAppCheck json check =
  case Json.eitherDecode json :: Either String Outline.Outline of
    Right (Outline.App app) -> check app
    Right other -> Test.assertFailure ("Expected App, got: " ++ show other)
    Left err -> Test.assertFailure ("JSON decode failed: " ++ err)

-- | Decode JSON as Pkg and assert success.
decodePkgSucceeds :: BL8.ByteString -> Test.Assertion
decodePkgSucceeds json =
  case Json.eitherDecode json :: Either String Outline.Outline of
    Right (Outline.Pkg _) -> pure ()
    Right other -> Test.assertFailure ("Expected Pkg, got: " ++ show other)
    Left err -> Test.assertFailure ("JSON decode failed: " ++ err)

-- | Decode JSON as Pkg and run a custom assertion.
decodePkgCheck :: BL8.ByteString -> (Outline.PkgOutline -> Test.Assertion) -> Test.Assertion
decodePkgCheck json check =
  case Json.eitherDecode json :: Either String Outline.Outline of
    Right (Outline.Pkg pkg) -> check pkg
    Right other -> Test.assertFailure ("Expected Pkg, got: " ++ show other)
    Left err -> Test.assertFailure ("JSON decode failed: " ++ err)

-- TEST JSON DATA

appJsonMinimal :: BL8.ByteString
appJsonMinimal =
  BL8.pack $
    concat
      [ "{",
        "\"type\":\"application\",",
        "\"canopy-version\":\"0.19.1\",",
        "\"source-directories\":[\"src\"],",
        "\"dependencies\":{\"direct\":{},\"indirect\":{}},",
        "\"test-dependencies\":{\"direct\":{}}",
        "}"
      ]

appJsonWithElmVersion :: BL8.ByteString
appJsonWithElmVersion =
  BL8.pack $
    concat
      [ "{",
        "\"type\":\"application\",",
        "\"elm-version\":\"0.19.1\",",
        "\"source-directories\":[\"src\"],",
        "\"dependencies\":{\"direct\":{},\"indirect\":{}},",
        "\"test-dependencies\":{\"direct\":{}}",
        "}"
      ]

appJsonWithScripts :: BL8.ByteString
appJsonWithScripts =
  BL8.pack $
    concat
      [ "{",
        "\"type\":\"application\",",
        "\"canopy-version\":\"0.19.1\",",
        "\"source-directories\":[\"src\"],",
        "\"dependencies\":{\"direct\":{},\"indirect\":{}},",
        "\"test-dependencies\":{\"direct\":{}},",
        "\"scripts\":{\"prebuild\":\"echo hello\",\"postbuild\":\"echo done\"}",
        "}"
      ]

appJsonWithEmptyScripts :: BL8.ByteString
appJsonWithEmptyScripts =
  BL8.pack $
    concat
      [ "{",
        "\"type\":\"application\",",
        "\"canopy-version\":\"0.19.1\",",
        "\"source-directories\":[\"src\"],",
        "\"dependencies\":{\"direct\":{},\"indirect\":{}},",
        "\"test-dependencies\":{\"direct\":{}},",
        "\"scripts\":{}",
        "}"
      ]

appJsonWithRepo :: BL8.ByteString
appJsonWithRepo =
  BL8.pack $
    concat
      [ "{",
        "\"type\":\"application\",",
        "\"canopy-version\":\"0.19.1\",",
        "\"source-directories\":[\"src\"],",
        "\"dependencies\":{\"direct\":{},\"indirect\":{}},",
        "\"test-dependencies\":{\"direct\":{}},",
        "\"repository\":\"https://github.com/example/project\"",
        "}"
      ]

appJsonWithBothOptional :: BL8.ByteString
appJsonWithBothOptional =
  BL8.pack $
    concat
      [ "{",
        "\"type\":\"application\",",
        "\"canopy-version\":\"0.19.1\",",
        "\"source-directories\":[\"src\"],",
        "\"dependencies\":{\"direct\":{},\"indirect\":{}},",
        "\"test-dependencies\":{\"direct\":{}},",
        "\"scripts\":{\"prebuild\":\"echo hello\"},",
        "\"repository\":\"https://github.com/example/project\"",
        "}"
      ]

pkgJsonMinimal :: BL8.ByteString
pkgJsonMinimal =
  BL8.pack $
    concat
      [ "{",
        "\"type\":\"package\",",
        "\"name\":\"author/project\",",
        "\"summary\":\"A test package\",",
        "\"license\":\"BSD-3-Clause\",",
        "\"version\":\"1.0.0\",",
        "\"exposed-modules\":[\"Main\"],",
        "\"canopy-version\":\"0.19.1 <= v < 0.20.0\",",
        "\"dependencies\":{},",
        "\"test-dependencies\":{}",
        "}"
      ]
