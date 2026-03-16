{-# LANGUAGE OverloadedStrings #-}

-- | Tests for coverage scope filtering, package grouping, coverage breakdown,
-- merge operations, and uncovered location detection.
--
-- @since 0.19.2
module Unit.Test.CoverageScopeTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LChar8
import qualified Data.Map.Strict as Map
import qualified Generate.JavaScript.Coverage as Coverage
import qualified Reporting.Annotation as Ann
import qualified Test.Coverage as TCoverage
import qualified Test.Coverage.Merge as Merge
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Coverage scope, breakdown, and merge"
    [ applyCoverageScopeTests,
      groupByPackageTests,
      coverageBreakdownTests,
      moduleBreakdownTests,
      mergeIstanbulTests,
      mergeLCOVTests,
      coverageFormatTests,
      checkThresholdScopeTests
    ]

-- HELPERS

nameStr :: String -> Name.Name
nameStr = Name.fromChars

mkPkg :: String -> String -> Pkg.Name
mkPkg author project = Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

mkCanonical :: Pkg.Name -> String -> ModuleName.Canonical
mkCanonical pkg modName = ModuleName.Canonical pkg (nameStr modName)

mkPoint :: Int -> Pkg.Name -> String -> String -> Coverage.CoveragePointType -> Coverage.CoveragePoint
mkPoint covId pkg modName defName covType =
  Coverage.CoveragePoint covId (nameStr modName) (nameStr defName) defaultRegion covType (mkCanonical pkg modName)
  where
    defaultRegion = Ann.Region (Ann.Position 1 1) (Ann.Position 1 1)

mkPointWithRegion :: Int -> Pkg.Name -> String -> String -> Coverage.CoveragePointType -> Ann.Region -> Coverage.CoveragePoint
mkPointWithRegion covId pkg modName defName covType region =
  Coverage.CoveragePoint covId (nameStr modName) (nameStr defName) region covType (mkCanonical pkg modName)

myPkg :: Pkg.Name
myPkg = mkPkg "canopy" "myapp"

depPkg :: Pkg.Name
depPkg = mkPkg "canopy" "core"

depPkg2 :: Pkg.Name
depPkg2 = mkPkg "canopy" "json"

renderBuilder :: BB.Builder -> String
renderBuilder = LChar8.unpack . BB.toLazyByteString

-- APPLY COVERAGE SCOPE TESTS

applyCoverageScopeTests :: TestTree
applyCoverageScopeTests =
  testGroup
    "applyCoverageScope"
    [ testCase "CurrentOnly filters to current package" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 depPkg "List" "map" Coverage.FunctionEntry)
              ])
            Coverage.CoverageMap filtered = TCoverage.applyCoverageScope TCoverage.CurrentOnly (Just myPkg) covMap
         in Map.size filtered @?= 1,
      testCase "WithAllDeps returns all points" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 depPkg "List" "map" Coverage.FunctionEntry)
              ])
            Coverage.CoverageMap filtered = TCoverage.applyCoverageScope TCoverage.WithAllDeps Nothing covMap
         in Map.size filtered @?= 2,
      testCase "WithSpecific includes current plus specified deps" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 depPkg "List" "map" Coverage.FunctionEntry)
              , (2, mkPoint 2 depPkg2 "Decode" "string" Coverage.FunctionEntry)
              ])
            Coverage.CoverageMap filtered = TCoverage.applyCoverageScope (TCoverage.WithSpecific [depPkg]) (Just myPkg) covMap
         in Map.size filtered @?= 2,
      testCase "CurrentOnly with Nothing returns all" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 depPkg "List" "map" Coverage.FunctionEntry)
              ])
            Coverage.CoverageMap filtered = TCoverage.applyCoverageScope TCoverage.CurrentOnly Nothing covMap
         in Map.size filtered @?= 2,
      testCase "WithSpecific without current package only includes specified" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 depPkg "List" "map" Coverage.FunctionEntry)
              , (2, mkPoint 2 depPkg2 "Decode" "string" Coverage.FunctionEntry)
              ])
            Coverage.CoverageMap filtered = TCoverage.applyCoverageScope (TCoverage.WithSpecific [depPkg2]) Nothing covMap
         in Map.size filtered @?= 1
    ]

-- GROUP BY PACKAGE TESTS

groupByPackageTests :: TestTree
groupByPackageTests =
  testGroup
    "groupByPackage"
    [ testCase "empty map produces empty groups" $
        Coverage.groupByPackage Map.empty @?= Map.empty,
      testCase "single point produces single group" $
        let pt = mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry
            groups = Coverage.groupByPackage (Map.singleton 0 pt)
         in Map.size groups @?= 1,
      testCase "two packages produce two groups" $
        let points = Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 depPkg "List" "map" Coverage.FunctionEntry)
              ]
            groups = Coverage.groupByPackage points
         in Map.size groups @?= 2,
      testCase "same package points are grouped together" $
        let points = Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 myPkg "Utils" "helper" Coverage.FunctionEntry)
              ]
            groups = Coverage.groupByPackage points
         in do
              Map.size groups @?= 1
              case Map.lookup myPkg groups of
                Just pts -> length pts @?= 2
                Nothing -> assertFailure "expected myPkg group"
    ]

-- COVERAGE BREAKDOWN TESTS

coverageBreakdownTests :: TestTree
coverageBreakdownTests =
  testGroup
    "computeBreakdown"
    [ testCase "empty map gives all zeros" $
        let bd = Coverage.computeBreakdown (Coverage.CoverageMap Map.empty) Map.empty
         in do
              Coverage._cbFunctions bd @?= (0, 0)
              Coverage._cbBranches bd @?= (0, 0)
              Coverage._cbStatements bd @?= (0, 0),
      testCase "all covered gives full counts" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 myPkg "Main" "bar" (Coverage.BranchArm 0 2))
              , (2, mkPoint 2 myPkg "Main" "baz" Coverage.TopLevelDef)
              ])
            hits = Map.fromList [(0, 5), (1, 3), (2, 1)]
            bd = Coverage.computeBreakdown covMap hits
         in do
              Coverage._cbFunctions bd @?= (1, 1)
              Coverage._cbBranches bd @?= (1, 1)
              Coverage._cbStatements bd @?= (3, 3),
      testCase "partially covered gives correct counts" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 myPkg "Main" "bar" Coverage.FunctionEntry)
              , (2, mkPoint 2 myPkg "Main" "if1" (Coverage.BranchArm 0 2))
              , (3, mkPoint 3 myPkg "Main" "if2" (Coverage.BranchArm 1 2))
              ])
            hits = Map.fromList [(0, 5), (1, 0), (2, 3), (3, 0)]
            bd = Coverage.computeBreakdown covMap hits
         in do
              Coverage._cbFunctions bd @?= (1, 2)
              Coverage._cbBranches bd @?= (1, 2)
              Coverage._cbStatements bd @?= (2, 4)
    ]

-- MODULE BREAKDOWN TESTS

moduleBreakdownTests :: TestTree
moduleBreakdownTests =
  testGroup
    "computeModuleBreakdown"
    [ testCase "empty map gives empty result" $
        Coverage.computeModuleBreakdown (Coverage.CoverageMap Map.empty) Map.empty @?= Map.empty,
      testCase "two modules produce two breakdowns" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 myPkg "Utils" "bar" Coverage.FunctionEntry)
              ])
            hits = Map.fromList [(0, 1), (1, 0)]
            result = Coverage.computeModuleBreakdown covMap hits
         in do
              Map.size result @?= 2
              case Map.lookup (nameStr "Main") result of
                Just bd -> Coverage._cbFunctions bd @?= (1, 1)
                Nothing -> assertFailure "expected Main module",
      testCase "module breakdown counts are correct" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "f1" Coverage.FunctionEntry)
              , (1, mkPoint 1 myPkg "Main" "b1" (Coverage.BranchArm 0 2))
              , (2, mkPoint 2 myPkg "Main" "b2" (Coverage.BranchArm 1 2))
              ])
            hits = Map.fromList [(0, 1), (1, 1), (2, 0)]
            result = Coverage.computeModuleBreakdown covMap hits
         in case Map.lookup (nameStr "Main") result of
              Just bd -> do
                Coverage._cbFunctions bd @?= (1, 1)
                Coverage._cbBranches bd @?= (1, 2)
                Coverage._cbStatements bd @?= (2, 3)
              Nothing -> assertFailure "expected Main module"
    ]

-- MERGE ISTANBUL TESTS

mergeIstanbulTests :: TestTree
mergeIstanbulTests =
  testGroup
    "mergeIstanbulValues"
    [ testCase "empty input returns error" $
        Merge.mergeIstanbulValues [] @?= Left Merge.EmptyInput,
      testCase "single value passes through" $
        let val = Aeson.object [("s", Aeson.object [("0", Aeson.Number 5)])]
         in Merge.mergeIstanbulValues [val] @?= Right val,
      testCase "summing hit counts in s map" $
        let v1 = Aeson.object [("s", Aeson.object [("0", Aeson.Number 3)])]
            v2 = Aeson.object [("s", Aeson.object [("0", Aeson.Number 7)])]
            result = Merge.mergeIstanbulValues [v1, v2]
         in case result of
              Right (Aeson.Object obj) ->
                case lookup' "s" obj of
                  Just (Aeson.Object smap) ->
                    case lookup' "0" smap of
                      Just (Aeson.Number n) -> n @?= 10
                      _ -> assertFailure "expected number for key 0"
                  _ -> assertFailure "expected s map"
              _ -> assertFailure "expected Right Object",
      testCase "disjoint keys are unioned" $
        let v1 = Aeson.object [("s", Aeson.object [("0", Aeson.Number 1)])]
            v2 = Aeson.object [("s", Aeson.object [("1", Aeson.Number 2)])]
            result = Merge.mergeIstanbulValues [v1, v2]
         in case result of
              Right (Aeson.Object obj) ->
                case lookup' "s" obj of
                  Just (Aeson.Object smap) -> do
                    case lookup' "0" smap of
                      Just (Aeson.Number n) -> n @?= 1
                      _ -> assertFailure "expected key 0"
                    case lookup' "1" smap of
                      Just (Aeson.Number n) -> n @?= 2
                      _ -> assertFailure "expected key 1"
                  _ -> assertFailure "expected s map"
              _ -> assertFailure "expected Right Object"
    ]
  where
    lookup' key obj =
      case Aeson.fromJSON (Aeson.Object obj) of
        Aeson.Success m -> Map.lookup (key :: String) (m :: Map.Map String Aeson.Value)
        _ -> Nothing

-- MERGE LCOV TESTS

mergeLCOVTests :: TestTree
mergeLCOVTests =
  testGroup
    "mergeLCOVFiles"
    [ testCase "empty input returns error" $ do
        result <- Merge.mergeLCOVFiles []
        case result of
          Left err -> err @?= Merge.EmptyInput
          Right _ -> assertFailure "expected Left EmptyInput"
    ]

-- COVERAGE FORMAT TESTS

coverageFormatTests :: TestTree
coverageFormatTests =
  testGroup
    "CoverageFormat"
    [ testCase "Istanbul show" $
        show TCoverage.Istanbul @?= "Istanbul",
      testCase "LCOV show" $
        show TCoverage.LCOV @?= "LCOV",
      testCase "Html show" $
        show TCoverage.Html @?= "Html",
      testCase "all three formats distinct" $ do
        assertBool "Istanbul /= LCOV" (TCoverage.Istanbul /= TCoverage.LCOV)
        assertBool "Istanbul /= Html" (TCoverage.Istanbul /= TCoverage.Html)
        assertBool "LCOV /= Html" (TCoverage.LCOV /= TCoverage.Html)
    ]

-- CHECK THRESHOLD WITH SCOPE TESTS

checkThresholdScopeTests :: TestTree
checkThresholdScopeTests =
  testGroup
    "checkThreshold with scope"
    [ testCase "WithAllDeps includes dependency coverage in threshold" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 depPkg "List" "map" Coverage.FunctionEntry)
              ])
            hits = Map.fromList [(0, 1), (1, 1)]
         in TCoverage.checkThreshold 100 TCoverage.WithAllDeps Nothing covMap hits @?= True,
      testCase "CurrentOnly excludes deps from threshold calculation" $
        let covMap = Coverage.CoverageMap (Map.fromList
              [ (0, mkPoint 0 myPkg "Main" "foo" Coverage.FunctionEntry)
              , (1, mkPoint 1 depPkg "List" "map" Coverage.FunctionEntry)
              ])
            hits = Map.singleton 0 1
         in TCoverage.checkThreshold 100 TCoverage.CurrentOnly (Just myPkg) covMap hits @?= True
    ]
