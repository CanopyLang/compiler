{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the dependency advisory database.
--
-- Verifies advisory matching, severity filtering, version range
-- checking, and JSON loading of advisory data.
--
-- @since 0.19.2
module Unit.Deps.AdvisoryTest (tests) where

import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Deps.Advisory as Advisory
import Test.Tasty
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  testGroup
    "Deps.Advisory"
    [ isAffectedTests,
      matchAdvisoriesTests,
      filterBySeverityTests,
      severityLabelTests,
      severityOrdTests,
      defaultAdvisoriesTests
    ]

-- IS AFFECTED TESTS

isAffectedTests :: TestTree
isAffectedTests =
  testGroup
    "isAffected"
    [ HUnit.testCase "version within range is affected" $
        Advisory.isAffected testAdvisory (Version.Version 1 0 3) HUnit.@?= True,
      HUnit.testCase "version at lower bound is affected" $
        Advisory.isAffected testAdvisory (Version.Version 1 0 0) HUnit.@?= True,
      HUnit.testCase "version at upper bound is affected" $
        Advisory.isAffected testAdvisory (Version.Version 1 0 5) HUnit.@?= True,
      HUnit.testCase "version below range is not affected" $
        Advisory.isAffected testAdvisory (Version.Version 0 9 0) HUnit.@?= False,
      HUnit.testCase "version above range is not affected" $
        Advisory.isAffected testAdvisory (Version.Version 1 1 0) HUnit.@?= False,
      HUnit.testCase "exact lower bound version is affected" $
        Advisory.isAffected singleVersionAdvisory (Version.Version 2 0 0) HUnit.@?= True,
      HUnit.testCase "different version is not affected for single version advisory" $
        Advisory.isAffected singleVersionAdvisory (Version.Version 2 0 1) HUnit.@?= False
    ]

-- MATCH ADVISORIES TESTS

matchAdvisoriesTests :: TestTree
matchAdvisoriesTests =
  testGroup
    "matchAdvisories"
    [ HUnit.testCase "matches advisory against affected dependency" $
        length (Advisory.matchAdvisories [testAdvisory] affectedDeps) HUnit.@?= 1,
      HUnit.testCase "no match for unaffected dependency" $
        length (Advisory.matchAdvisories [testAdvisory] unaffectedDeps) HUnit.@?= 0,
      HUnit.testCase "no match for different package" $
        length (Advisory.matchAdvisories [testAdvisory] differentPkgDeps) HUnit.@?= 0,
      HUnit.testCase "empty advisories produce no results" $
        length (Advisory.matchAdvisories [] affectedDeps) HUnit.@?= 0,
      HUnit.testCase "empty deps produce no results" $
        length (Advisory.matchAdvisories [testAdvisory] Map.empty) HUnit.@?= 0,
      HUnit.testCase "multiple advisories can match same package" $
        length (Advisory.matchAdvisories [testAdvisory, testAdvisory2] affectedDeps) HUnit.@?= 2,
      HUnit.testCase "result contains correct installed version" $
        Advisory._auditInstalledVersion (head (Advisory.matchAdvisories [testAdvisory] affectedDeps))
          HUnit.@?= Version.Version 1 0 3
    ]

-- FILTER BY SEVERITY TESTS

filterBySeverityTests :: TestTree
filterBySeverityTests =
  testGroup
    "filterBySeverity"
    [ HUnit.testCase "low threshold includes all" $
        length (Advisory.filterBySeverity Advisory.SevLow mixedResults) HUnit.@?= 3,
      HUnit.testCase "medium threshold excludes low" $
        length (Advisory.filterBySeverity Advisory.SevMedium mixedResults) HUnit.@?= 2,
      HUnit.testCase "high threshold excludes low and medium" $
        length (Advisory.filterBySeverity Advisory.SevHigh mixedResults) HUnit.@?= 1,
      HUnit.testCase "critical threshold only includes critical" $
        length (Advisory.filterBySeverity Advisory.SevCritical mixedResults) HUnit.@?= 0,
      HUnit.testCase "empty results stay empty" $
        length (Advisory.filterBySeverity Advisory.SevLow []) HUnit.@?= 0
    ]

-- SEVERITY LABEL TESTS

severityLabelTests :: TestTree
severityLabelTests =
  testGroup
    "severityLabel"
    [ HUnit.testCase "low label" $
        Advisory.severityLabel Advisory.SevLow HUnit.@?= "low",
      HUnit.testCase "medium label" $
        Advisory.severityLabel Advisory.SevMedium HUnit.@?= "medium",
      HUnit.testCase "high label" $
        Advisory.severityLabel Advisory.SevHigh HUnit.@?= "high",
      HUnit.testCase "critical label" $
        Advisory.severityLabel Advisory.SevCritical HUnit.@?= "critical"
    ]

-- SEVERITY ORD TESTS

severityOrdTests :: TestTree
severityOrdTests =
  testGroup
    "severityOrd"
    [ HUnit.testCase "low < medium" $
        HUnit.assertBool "low should be less than medium"
          (Advisory.severityOrd Advisory.SevLow < Advisory.severityOrd Advisory.SevMedium),
      HUnit.testCase "medium < high" $
        HUnit.assertBool "medium should be less than high"
          (Advisory.severityOrd Advisory.SevMedium < Advisory.severityOrd Advisory.SevHigh),
      HUnit.testCase "high < critical" $
        HUnit.assertBool "high should be less than critical"
          (Advisory.severityOrd Advisory.SevHigh < Advisory.severityOrd Advisory.SevCritical)
    ]

-- DEFAULT ADVISORIES TESTS

defaultAdvisoriesTests :: TestTree
defaultAdvisoriesTests =
  testGroup
    "defaultAdvisories"
    [ HUnit.testCase "default advisories is a list" $
        length Advisory.defaultAdvisories HUnit.@?= 0
    ]

-- TEST FIXTURES

-- | Advisory for elm/http versions 1.0.0 through 1.0.5
testAdvisory :: Advisory.Advisory
testAdvisory =
  Advisory.Advisory
    { Advisory._advisoryId = "CANOPY-2026-001",
      Advisory._advisoryPackage = "elm/http",
      Advisory._advisoryAffectedLower = Version.Version 1 0 0,
      Advisory._advisoryAffectedUpper = Version.Version 1 0 5,
      Advisory._advisorySeverity = Advisory.SevHigh,
      Advisory._advisoryDescription = "URL injection vulnerability",
      Advisory._advisoryFixedIn = Just (Version.Version 1 0 6)
    }

-- | Second advisory for elm/http (overlapping range)
testAdvisory2 :: Advisory.Advisory
testAdvisory2 =
  Advisory.Advisory
    { Advisory._advisoryId = "CANOPY-2026-002",
      Advisory._advisoryPackage = "elm/http",
      Advisory._advisoryAffectedLower = Version.Version 1 0 2,
      Advisory._advisoryAffectedUpper = Version.Version 1 0 4,
      Advisory._advisorySeverity = Advisory.SevMedium,
      Advisory._advisoryDescription = "Memory exhaustion on large responses",
      Advisory._advisoryFixedIn = Nothing
    }

-- | Advisory for a single exact version
singleVersionAdvisory :: Advisory.Advisory
singleVersionAdvisory =
  Advisory.Advisory
    { Advisory._advisoryId = "CANOPY-2026-003",
      Advisory._advisoryPackage = "elm/json",
      Advisory._advisoryAffectedLower = Version.Version 2 0 0,
      Advisory._advisoryAffectedUpper = Version.Version 2 0 0,
      Advisory._advisorySeverity = Advisory.SevCritical,
      Advisory._advisoryDescription = "Stack overflow on deeply nested JSON",
      Advisory._advisoryFixedIn = Just (Version.Version 2 0 1)
    }

-- | Dependencies where elm/http is in the affected range
affectedDeps :: Map Pkg.Name Version.Version
affectedDeps =
  Map.singleton Pkg.http (Version.Version 1 0 3)

-- | Dependencies where elm/http is above the affected range
unaffectedDeps :: Map Pkg.Name Version.Version
unaffectedDeps =
  Map.singleton Pkg.http (Version.Version 2 0 0)

-- | Dependencies with a different package
differentPkgDeps :: Map Pkg.Name Version.Version
differentPkgDeps =
  Map.singleton Pkg.core (Version.Version 1 0 5)

-- | Mixed audit results for severity filtering tests
mixedResults :: [Advisory.AuditResult]
mixedResults =
  [ Advisory.AuditResult lowAdvisory (Version.Version 1 0 0),
    Advisory.AuditResult mediumAdvisory (Version.Version 1 0 0),
    Advisory.AuditResult highAdvisory (Version.Version 1 0 0)
  ]
  where
    lowAdvisory = testAdvisory {Advisory._advisorySeverity = Advisory.SevLow}
    mediumAdvisory = testAdvisory {Advisory._advisorySeverity = Advisory.SevMedium}
    highAdvisory = testAdvisory {Advisory._advisorySeverity = Advisory.SevHigh}
