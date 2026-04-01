{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.Mode'.
--
-- Covers:
--   * 'globalName' — dev mode always returns Nothing; prod mode returns
--     Just when the global has a mapping, Nothing when it does not
--   * 'isDebug' / 'isCoverage' — mode predicate correctness
--   * 'isFFIStrict' — inverted ffiUnsafe flag semantics
--   * 'isFFIAlias' — membership test against the alias set
--   * 'isESM' — output format predicate
--
-- @since 0.20.4
module Unit.Generate.ModeTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Canopy.Data.Name as Name
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Test.Tasty
import Test.Tasty.HUnit


tests :: TestTree
tests =
  testGroup
    "Generate.Mode"
    [ globalNameTests,
      isDebugTests,
      isCoverageTests,
      isFFIStrictTests,
      isFFIAliasTests,
      isESMTests
    ]


-- GLOBAL NAME TESTS

globalNameTests :: TestTree
globalNameTests =
  testGroup
    "globalName"
    [ testCase "dev mode always returns Nothing for any global" $
        let mode = devMode
         in Mode.globalName mode testGlobal @?= Nothing,
      testCase "prod mode returns Just when global is in rename map" $
        let mode = prodModeWithRenames (Map.singleton testGlobal (Name.fromChars "a"))
         in Mode.globalName mode testGlobal @?= Just (Name.fromChars "a"),
      testCase "prod mode returns Nothing when global is NOT in rename map" $
        let mode = prodModeWithRenames Map.empty
         in Mode.globalName mode testGlobal @?= Nothing,
      testCase "prod mode returns correct short name for mapped global" $
        let shortName = Name.fromChars "z"
            mode = prodModeWithRenames (Map.singleton testGlobal shortName)
         in Mode.globalName mode testGlobal @?= Just shortName,
      testCase "prod mode returns Nothing for a different global not in map" $
        let mode = prodModeWithRenames (Map.singleton testGlobal (Name.fromChars "a"))
            otherGlobal = Opt.Global testHome (Name.fromChars "other")
         in Mode.globalName mode otherGlobal @?= Nothing
    ]


-- IS DEBUG TESTS

isDebugTests :: TestTree
isDebugTests =
  testGroup
    "isDebug"
    [ testCase "dev mode with debug types is debug" $
        Mode.isDebug devMode @?= True,
      testCase "dev mode without debug types is not debug" $
        Mode.isDebug devModeNoDebug @?= False,
      testCase "prod mode is never debug" $
        Mode.isDebug prodMode @?= False
    ]


-- IS COVERAGE TESTS

isCoverageTests :: TestTree
isCoverageTests =
  testGroup
    "isCoverage"
    [ testCase "dev mode with coverage enabled returns True" $
        Mode.isCoverage devModeCoverage @?= True,
      testCase "dev mode without coverage returns False" $
        Mode.isCoverage devMode @?= False,
      testCase "prod mode is never coverage" $
        Mode.isCoverage prodMode @?= False
    ]


-- IS FFI STRICT TESTS

isFFIStrictTests :: TestTree
isFFIStrictTests =
  testGroup
    "isFFIStrict"
    [ testCase "dev mode default (ffiUnsafe=False) means strict=True" $
        Mode.isFFIStrict devMode @?= True,
      testCase "dev mode with ffiUnsafe=True means strict=False" $
        Mode.isFFIStrict devModeUnsafe @?= False,
      testCase "prod mode default means strict=True" $
        Mode.isFFIStrict prodMode @?= True
    ]


-- IS FFI ALIAS TESTS

isFFIAliasTests :: TestTree
isFFIAliasTests =
  testGroup
    "isFFIAlias"
    [ testCase "name in dev alias set returns True" $
        let aliasName = Name.fromChars "MyFFIModule"
            mode = devModeWithAliases (Set.singleton aliasName)
         in Mode.isFFIAlias mode aliasName @?= True,
      testCase "name not in dev alias set returns False" $
        let aliasName = Name.fromChars "MyFFIModule"
            mode = devModeWithAliases Set.empty
         in Mode.isFFIAlias mode aliasName @?= False,
      testCase "name in prod alias set returns True" $
        let aliasName = Name.fromChars "SomeForeignModule"
            mode = prodModeWithAliases (Set.singleton aliasName)
         in Mode.isFFIAlias mode aliasName @?= True,
      testCase "name not in prod alias set returns False" $
        let aliasName = Name.fromChars "SomeForeignModule"
            mode = prodModeWithAliases Set.empty
         in Mode.isFFIAlias mode aliasName @?= False
    ]


-- IS ESM TESTS

isESMTests :: TestTree
isESMTests =
  testGroup
    "isESM"
    [ testCase "FormatESM is ESM" $
        Mode.isESM Mode.FormatESM @?= True,
      testCase "FormatIIFE is not ESM" $
        Mode.isESM Mode.FormatIIFE @?= False
    ]


-- HELPERS

testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical Pkg.core (Name.fromChars "Test")

testGlobal :: Opt.Global
testGlobal = Opt.Global testHome (Name.fromChars "myFunc")

-- | Dev mode with debug types enabled (coverage=False, ffiUnsafe=False, etc.)
devMode :: Mode.Mode
devMode = Mode.Dev (Just (error "dummy types")) False False False Set.empty False

-- | Dev mode without debug types (coverage=False).
devModeNoDebug :: Mode.Mode
devModeNoDebug = Mode.Dev Nothing False False False Set.empty False

-- | Dev mode with coverage enabled.
devModeCoverage :: Mode.Mode
devModeCoverage = Mode.Dev Nothing False False False Set.empty True

-- | Dev mode with ffiUnsafe=True.
devModeUnsafe :: Mode.Mode
devModeUnsafe = Mode.Dev Nothing False True False Set.empty False

-- | Dev mode with a specific set of FFI alias names.
devModeWithAliases :: Set.Set Name.Name -> Mode.Mode
devModeWithAliases aliases = Mode.Dev Nothing False False False aliases False

-- | Prod mode with all defaults (no rename map, no aliases).
prodMode :: Mode.Mode
prodMode =
  Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty Map.empty

-- | Prod mode with a specific global rename map.
prodModeWithRenames :: Map.Map Opt.Global Name.Name -> Mode.Mode
prodModeWithRenames renames =
  Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty renames

-- | Prod mode with a specific set of FFI alias names.
prodModeWithAliases :: Set.Set Name.Name -> Mode.Mode
prodModeWithAliases aliases =
  Mode.Prod Map.empty False False False StringPool.emptyPool aliases Map.empty
