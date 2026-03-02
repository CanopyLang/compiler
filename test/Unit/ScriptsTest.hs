{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the Scripts module (canopy.json script hooks).
--
-- Verifies script lookup, existence checks, and integration with
-- the AppOutline type. Actual script execution is not tested here
-- since that requires spawning system processes.
--
-- @since 0.19.2
module Unit.ScriptsTest (tests) where

import qualified Canopy.Constraint as Constraint
import qualified Canopy.Outline as Outline
import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Scripts (ScriptResult (..))
import qualified Scripts
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Scripts"
    [ lookupTests,
      hasScriptTests,
      outlineFieldTests
    ]

-- LOOKUP TESTS

lookupTests :: TestTree
lookupTests =
  Test.testGroup
    "lookupScript"
    [ Test.testCase "finds existing script" $
        Scripts.lookupScript "prebuild" appWithScripts
          @?= Just "echo prebuild",
      Test.testCase "finds postbuild script" $
        Scripts.lookupScript "postbuild" appWithScripts
          @?= Just "echo postbuild",
      Test.testCase "returns Nothing for missing script" $
        Scripts.lookupScript "nonexistent" appWithScripts
          @?= Nothing,
      Test.testCase "returns Nothing when no scripts field" $
        Scripts.lookupScript "prebuild" appWithoutScripts
          @?= Nothing,
      Test.testCase "returns Nothing for empty scripts map" $
        Scripts.lookupScript "prebuild" appWithEmptyScripts
          @?= Nothing
    ]

-- HAS SCRIPT TESTS

hasScriptTests :: TestTree
hasScriptTests =
  Test.testGroup
    "hasScript"
    [ Test.testCase "True for existing script" $
        Scripts.hasScript "prebuild" appWithScripts @?= True,
      Test.testCase "False for missing script" $
        Scripts.hasScript "nonexistent" appWithScripts @?= False,
      Test.testCase "False when no scripts field" $
        Scripts.hasScript "prebuild" appWithoutScripts @?= False
    ]

-- OUTLINE FIELD TESTS

outlineFieldTests :: TestTree
outlineFieldTests =
  Test.testGroup
    "AppOutline fields"
    [ Test.testCase "scripts field round-trips through JSON" $ do
        let encoded = Outline._appScripts appWithScripts
        encoded @?= Just scriptsMap,
      Test.testCase "repository field is preserved" $
        Outline._appRepository appWithRepo @?= Just "https://github.com/example/project",
      Test.testCase "repository field defaults to Nothing" $
        Outline._appRepository appWithoutScripts @?= Nothing,
      Test.testCase "scripts field defaults to Nothing" $
        Outline._appScripts appWithoutScripts @?= Nothing
    ]

-- HELPERS

scriptsMap :: Map.Map Text.Text Text.Text
scriptsMap =
  Map.fromList
    [ ("prebuild", "echo prebuild"),
      ("postbuild", "echo postbuild"),
      ("test", "canopy-test")
    ]

-- | Application outline with scripts defined.
appWithScripts :: Outline.AppOutline
appWithScripts =
  Outline.AppOutline
    { Outline._appCanopy = Version.compiler,
      Outline._appSrcDirs = [Outline.RelativeSrcDir "src"],
      Outline._appDeps = Map.empty,
      Outline._appTestDeps = Map.empty,
      Outline._appDepsDirect = Map.empty,
      Outline._appDepsIndirect = Map.empty,
      Outline._appTestDepsDirect = Map.empty,
      Outline._appScripts = Just scriptsMap,
      Outline._appRepository = Nothing,
      Outline._appCapabilities = Set.empty
    }

-- | Application outline without scripts.
appWithoutScripts :: Outline.AppOutline
appWithoutScripts =
  Outline.AppOutline
    { Outline._appCanopy = Version.compiler,
      Outline._appSrcDirs = [Outline.RelativeSrcDir "src"],
      Outline._appDeps = Map.empty,
      Outline._appTestDeps = Map.empty,
      Outline._appDepsDirect = Map.empty,
      Outline._appDepsIndirect = Map.empty,
      Outline._appTestDepsDirect = Map.empty,
      Outline._appScripts = Nothing,
      Outline._appRepository = Nothing,
      Outline._appCapabilities = Set.empty
    }

-- | Application outline with empty scripts map.
appWithEmptyScripts :: Outline.AppOutline
appWithEmptyScripts =
  Outline.AppOutline
    { Outline._appCanopy = Version.compiler,
      Outline._appSrcDirs = [Outline.RelativeSrcDir "src"],
      Outline._appDeps = Map.empty,
      Outline._appTestDeps = Map.empty,
      Outline._appDepsDirect = Map.empty,
      Outline._appDepsIndirect = Map.empty,
      Outline._appTestDepsDirect = Map.empty,
      Outline._appScripts = Just Map.empty,
      Outline._appRepository = Nothing,
      Outline._appCapabilities = Set.empty
    }

-- | Application outline with repository field.
appWithRepo :: Outline.AppOutline
appWithRepo =
  Outline.AppOutline
    { Outline._appCanopy = Version.compiler,
      Outline._appSrcDirs = [Outline.RelativeSrcDir "src"],
      Outline._appDeps = Map.empty,
      Outline._appTestDeps = Map.empty,
      Outline._appDepsDirect = Map.empty,
      Outline._appDepsIndirect = Map.empty,
      Outline._appTestDepsDirect = Map.empty,
      Outline._appScripts = Nothing,
      Outline._appRepository = Just "https://github.com/example/project",
      Outline._appCapabilities = Set.empty
    }
