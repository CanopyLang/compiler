{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.Mode'.
--
-- Covers:
--   * 'globalName' — dev mode always returns Nothing; prod mode returns
--     Just when the global has a mapping, Nothing when it does not
--   * 'isDebug' / 'isCoverage' — mode predicate correctness
--   * 'isFFIStrict' — inverted ffiUnsafe flag semantics
--   * 'isFFIDebug' — ffiDebug flag semantics
--   * 'isElmCompatible' — elm-compat flag propagation
--   * 'isFFIAlias' — membership test against the alias set
--   * 'isESM' — output format predicate
--   * 'stringPool' — dev returns empty pool; prod returns stored pool
--   * 'shortenFieldNames' — assigns unique short names to each field
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
      isFFIDebugTests,
      isElmCompatibleTests,
      isFFIAliasTests,
      isESMTests,
      stringPoolTests,
      shortenFieldNamesTests
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


-- IS FFI DEBUG TESTS

isFFIDebugTests :: TestTree
isFFIDebugTests =
  testGroup
    "isFFIDebug"
    [ testCase "dev mode default (ffiDebug=False) returns False" $
        Mode.isFFIDebug devMode @?= False,
      testCase "dev mode with ffiDebug=True returns True" $
        Mode.isFFIDebug devModeFFIDebug @?= True,
      testCase "prod mode default returns False" $
        Mode.isFFIDebug prodMode @?= False,
      testCase "prod mode with ffiDebug=True returns True" $
        Mode.isFFIDebug prodModeFFIDebug @?= True
    ]


-- IS ELM COMPATIBLE TESTS

isElmCompatibleTests :: TestTree
isElmCompatibleTests =
  testGroup
    "isElmCompatible"
    [ testCase "dev mode default (elmCompat=False) returns False" $
        Mode.isElmCompatible devMode @?= False,
      testCase "dev mode with elmCompat=True returns True" $
        Mode.isElmCompatible devModeElmCompat @?= True,
      testCase "prod mode default (elmCompat=False) returns False" $
        Mode.isElmCompatible prodMode @?= False,
      testCase "prod mode with elmCompat=True returns True" $
        Mode.isElmCompatible prodModeElmCompat @?= True
    ]


-- STRING POOL TESTS

stringPoolTests :: TestTree
stringPoolTests =
  testGroup
    "stringPool"
    [ testCase "dev mode returns the same pool as emptyPool" $
        show (Mode.stringPool devMode) @?= show StringPool.emptyPool,
      testCase "prod mode with emptyPool returns the same pool" $
        show (Mode.stringPool prodMode) @?= show StringPool.emptyPool
    ]


-- SHORTEN FIELD NAMES TESTS

shortenFieldNamesTests :: TestTree
shortenFieldNamesTests =
  testGroup
    "shortenFieldNames"
    [ testCase "empty graph yields empty short-name map" $
        Map.size (Mode.shortenFieldNames Opt.empty) @?= 0,

      testCase "graph with one field yields one short name" $
        let graph = Opt.GlobalGraph Map.empty (Map.singleton (Name.fromChars "name") 5) Map.empty
         in Map.size (Mode.shortenFieldNames graph) @?= 1,

      testCase "graph with two fields yields two distinct short names" $
        let fields = Map.fromList
              [ (Name.fromChars "name", 3),
                (Name.fromChars "age", 1)
              ]
            graph = Opt.GlobalGraph Map.empty fields Map.empty
         in Map.size (Mode.shortenFieldNames graph) @?= 2,

      testCase "known field name appears in the result map" $
        let fieldName = Name.fromChars "email"
            graph = Opt.GlobalGraph Map.empty (Map.singleton fieldName 7) Map.empty
         in Map.member fieldName (Mode.shortenFieldNames graph) @?= True
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

-- | Dev mode with ffiDebug=True.
devModeFFIDebug :: Mode.Mode
devModeFFIDebug = Mode.Dev Nothing False False True Set.empty False

-- | Prod mode with ffiDebug=True.
prodModeFFIDebug :: Mode.Mode
prodModeFFIDebug = Mode.Prod Map.empty False False True StringPool.emptyPool Set.empty Map.empty

-- | Dev mode with Elm compatibility enabled.
devModeElmCompat :: Mode.Mode
devModeElmCompat = Mode.Dev Nothing True False False Set.empty False

-- | Prod mode with Elm compatibility enabled.
prodModeElmCompat :: Mode.Mode
prodModeElmCompat = Mode.Prod Map.empty True False False StringPool.emptyPool Set.empty Map.empty
