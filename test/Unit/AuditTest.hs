{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the dependency audit command.
--
-- Verifies outline analysis, advisory finding generation, severity
-- filtering, format output, and flag parsing.
--
-- @since 0.19.2
module Unit.AuditTest (tests) where

import qualified Audit
import qualified Canopy.Constraint as Constraint
import qualified Canopy.Licenses as Licenses
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Canopy.Data.Utf8 as Utf8
import qualified Data.Map.Strict as Map
import qualified Deps.Advisory as Advisory
import Test.Tasty
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  testGroup
    "Audit"
    [ analyzeOutlineTests,
      advisoryFindingsTests,
      checkDirectDepsTests,
      checkIndirectDepsTests,
      formatSummaryTests,
      severityPrefixTests,
      severityLabelTests,
      parseSeverityFlagTests
    ]

-- ANALYZE OUTLINE TESTS

analyzeOutlineTests :: TestTree
analyzeOutlineTests =
  testGroup
    "analyzeOutline"
    [ HUnit.testCase "app with pre-1.0 dep produces info finding" $
        let outline = Outline.App appWithPre1Dep
            findings = Audit.analyzeOutline outline
         in HUnit.assertBool "should have info finding"
              (any (\(Audit.Finding sev _ _ _) -> sev == Audit.Info) findings),
      HUnit.testCase "app with stable deps produces no warnings" $
        let outline = Outline.App appWithStableDeps
            findings = Audit.analyzeOutline outline
         in HUnit.assertBool "should have no warnings or critical"
              (all (\(Audit.Finding sev _ _ _) -> sev == Audit.Info) findings),
      HUnit.testCase "pkg outline produces dependency count finding" $
        let outline = Outline.Pkg pkgOutline
            findings = Audit.analyzeOutline outline
         in length findings HUnit.@?= 1
    ]

-- ADVISORY FINDINGS TESTS

advisoryFindingsTests :: TestTree
advisoryFindingsTests =
  testGroup
    "advisoryFindings"
    [ HUnit.testCase "matching advisory produces critical finding" $
        let findings = Audit.advisoryFindings [testAdvisory] (Outline.App appWithAffectedDep) Map.empty
         in length findings HUnit.@?= 1,
      HUnit.testCase "non-matching advisory produces no findings" $
        let findings = Audit.advisoryFindings [testAdvisory] (Outline.App appWithStableDeps) Map.empty
         in length findings HUnit.@?= 0,
      HUnit.testCase "lock file deps override outline deps" $
        let lockDeps = Map.singleton Pkg.http (Version.Version 2 0 0)
            findings = Audit.advisoryFindings [testAdvisory] (Outline.App appWithAffectedDep) lockDeps
         in length findings HUnit.@?= 0,
      HUnit.testCase "empty advisories produce no findings" $
        let findings = Audit.advisoryFindings [] (Outline.App appWithAffectedDep) Map.empty
         in length findings HUnit.@?= 0,
      HUnit.testCase "advisory finding contains fix suggestion" $
        let findings = Audit.advisoryFindings [testAdvisory] (Outline.App appWithAffectedDep) Map.empty
         in case findings of
              [Audit.Finding _ _ _ mFix] ->
                HUnit.assertBool "should have fix suggestion" (mFix /= Nothing)
              _ -> HUnit.assertFailure "expected exactly one finding"
    ]

-- CHECK DIRECT DEPS TESTS

checkDirectDepsTests :: TestTree
checkDirectDepsTests =
  testGroup
    "checkDirectDeps"
    [ HUnit.testCase "empty deps produce no findings" $
        Audit.checkDirectDeps Map.empty HUnit.@?= [],
      HUnit.testCase "stable dep produces no findings" $
        Audit.checkDirectDeps stableDeps HUnit.@?= [],
      HUnit.testCase "pre-1.0 dep produces info finding" $
        length (Audit.checkDirectDeps pre1Deps) HUnit.@?= 1,
      HUnit.testCase "pre-1.0 finding has Info severity" $
        case Audit.checkDirectDeps pre1Deps of
          [Audit.Finding sev _ _ _] -> sev HUnit.@?= Audit.Info
          _ -> HUnit.assertFailure "expected exactly one finding"
    ]

-- CHECK INDIRECT DEPS TESTS

checkIndirectDepsTests :: TestTree
checkIndirectDepsTests =
  testGroup
    "checkIndirectDeps"
    [ HUnit.testCase "small indirect tree produces no findings" $
        Audit.checkIndirectDeps smallIndirectDeps HUnit.@?= [],
      HUnit.testCase "large indirect tree produces warning" $
        length (Audit.checkIndirectDeps largeIndirectDeps) HUnit.@?= 1,
      HUnit.testCase "large tree finding has Warning severity" $
        case Audit.checkIndirectDeps largeIndirectDeps of
          [Audit.Finding sev _ _ _] -> sev HUnit.@?= Audit.Warning
          _ -> HUnit.assertFailure "expected exactly one finding"
    ]

-- FORMAT SUMMARY TESTS

formatSummaryTests :: TestTree
formatSummaryTests =
  testGroup
    "formatSummary"
    [ HUnit.testCase "all zeros" $
        Audit.formatSummary 0 0 0 HUnit.@?= "Audit complete: 0 critical, 0 warnings, 0 info",
      HUnit.testCase "mixed counts" $
        Audit.formatSummary 1 2 3 HUnit.@?= "Audit complete: 1 critical, 2 warnings, 3 info"
    ]

-- SEVERITY PREFIX TESTS

severityPrefixTests :: TestTree
severityPrefixTests =
  testGroup
    "severityPrefix"
    [ HUnit.testCase "Info prefix" $
        Audit.severityPrefix Audit.Info HUnit.@?= "[info]",
      HUnit.testCase "Warning prefix" $
        Audit.severityPrefix Audit.Warning HUnit.@?= "[warn]",
      HUnit.testCase "Critical prefix" $
        Audit.severityPrefix Audit.Critical HUnit.@?= "[CRITICAL]"
    ]

-- SEVERITY LABEL TESTS

severityLabelTests :: TestTree
severityLabelTests =
  testGroup
    "severityLabel"
    [ HUnit.testCase "Info label" $
        Audit.severityLabel Audit.Info HUnit.@?= "info",
      HUnit.testCase "Warning label" $
        Audit.severityLabel Audit.Warning HUnit.@?= "warning",
      HUnit.testCase "Critical label" $
        Audit.severityLabel Audit.Critical HUnit.@?= "critical"
    ]

-- PARSE SEVERITY FLAG TESTS

parseSeverityFlagTests :: TestTree
parseSeverityFlagTests =
  testGroup
    "parseSeverityFlag"
    [ HUnit.testCase "parses info" $
        Audit.parseSeverityFlag "info" HUnit.@?= Just Audit.Info,
      HUnit.testCase "parses warning" $
        Audit.parseSeverityFlag "warning" HUnit.@?= Just Audit.Warning,
      HUnit.testCase "parses critical" $
        Audit.parseSeverityFlag "critical" HUnit.@?= Just Audit.Critical,
      HUnit.testCase "rejects unknown" $
        Audit.parseSeverityFlag "invalid" HUnit.@?= Nothing,
      HUnit.testCase "rejects empty" $
        Audit.parseSeverityFlag "" HUnit.@?= Nothing
    ]

-- TEST FIXTURES

-- | Advisory for elm/http 1.0.0 through 1.0.5
testAdvisory :: Advisory.Advisory
testAdvisory =
  Advisory.Advisory
    { Advisory._advisoryId = "CANOPY-2026-001",
      Advisory._advisoryPackage = "canopy/http",
      Advisory._advisoryAffectedLower = Version.Version 1 0 0,
      Advisory._advisoryAffectedUpper = Version.Version 1 0 5,
      Advisory._advisorySeverity = Advisory.SevHigh,
      Advisory._advisoryDescription = "URL injection vulnerability",
      Advisory._advisoryFixedIn = Just (Version.Version 1 0 6)
    }

-- | App outline with a pre-1.0 dependency
appWithPre1Dep :: Outline.AppOutline
appWithPre1Dep =
  Outline.AppOutline
    { Outline._appCanopy = Version.Version 0 19 1,
      Outline._appSrcDirs = [Outline.AbsoluteSrcDir "src"],
      Outline._appDeps = Map.empty,
      Outline._appTestDeps = Map.empty,
      Outline._appDepsDirect = Map.singleton Pkg.core (Version.Version 0 9 0),
      Outline._appDepsIndirect = Map.empty,
      Outline._appTestDepsDirect = Map.empty,
      Outline._appScripts = Nothing,
      Outline._appRepository = Nothing
    }

-- | App outline with stable (>= 1.0) dependencies
appWithStableDeps :: Outline.AppOutline
appWithStableDeps =
  Outline.AppOutline
    { Outline._appCanopy = Version.Version 0 19 1,
      Outline._appSrcDirs = [Outline.AbsoluteSrcDir "src"],
      Outline._appDeps = Map.empty,
      Outline._appTestDeps = Map.empty,
      Outline._appDepsDirect = Map.singleton Pkg.core (Version.Version 1 0 5),
      Outline._appDepsIndirect = Map.empty,
      Outline._appTestDepsDirect = Map.empty,
      Outline._appScripts = Nothing,
      Outline._appRepository = Nothing
    }

-- | App outline with a dependency affected by the test advisory
appWithAffectedDep :: Outline.AppOutline
appWithAffectedDep =
  Outline.AppOutline
    { Outline._appCanopy = Version.Version 0 19 1,
      Outline._appSrcDirs = [Outline.AbsoluteSrcDir "src"],
      Outline._appDeps = Map.empty,
      Outline._appTestDeps = Map.empty,
      Outline._appDepsDirect = Map.singleton Pkg.http (Version.Version 1 0 3),
      Outline._appDepsIndirect = Map.empty,
      Outline._appTestDepsDirect = Map.empty,
      Outline._appScripts = Nothing,
      Outline._appRepository = Nothing
    }

-- | Package outline with some deps
pkgOutline :: Outline.PkgOutline
pkgOutline =
  Outline.PkgOutline
    { Outline._pkgName = Pkg.core,
      Outline._pkgSummary = Outline.defaultSummary,
      Outline._pkgLicense = Licenses.bsd3,
      Outline._pkgVersion = Version.one,
      Outline._pkgExposed = Outline.ExposedList [],
      Outline._pkgDeps = Map.singleton Pkg.core Constraint.anything,
      Outline._pkgTestDeps = Map.empty,
      Outline._pkgCanopy = Constraint.defaultCanopy
    }

-- | Stable direct dependencies
stableDeps :: Map.Map Pkg.Name Version.Version
stableDeps =
  Map.singleton Pkg.core (Version.Version 1 0 5)

-- | Pre-1.0 direct dependencies
pre1Deps :: Map.Map Pkg.Name Version.Version
pre1Deps =
  Map.singleton Pkg.core (Version.Version 0 9 0)

-- | Small indirect dependency tree (under threshold)
smallIndirectDeps :: Map.Map Pkg.Name Version.Version
smallIndirectDeps =
  Map.fromList
    [ (Pkg.core, Version.Version 1 0 5),
      (Pkg.json, Version.Version 1 1 3)
    ]

-- | Large indirect dependency tree (over 20 threshold).
--
-- We build a map with more than 20 distinct package names by
-- using the well-known packages and constructing additional ones
-- using the exported Pkg.Name constructor with Utf8.fromChars.
largeIndirectDeps :: Map.Map Pkg.Name Version.Version
largeIndirectDeps =
  Map.fromList (zip packageNames (repeat (Version.Version 1 0 0)))
  where
    packageNames =
      [ Pkg.core,
        Pkg.browser,
        Pkg.virtualDom,
        Pkg.html,
        Pkg.json,
        Pkg.http,
        Pkg.url,
        Pkg.webgl,
        Pkg.linearAlgebra,
        Pkg.test
      ]
        ++ fmap makeTestPkg [1 .. 12 :: Int]

    makeTestPkg n =
      Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars ("pkg" ++ show n))
