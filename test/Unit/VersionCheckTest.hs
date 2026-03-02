{-# LANGUAGE OverloadedStrings #-}

-- | Tests for compiler version checking against project requirements.
--
-- Verifies that 'checkCompilerVersion' correctly identifies compatible
-- and incompatible version configurations for both application and
-- package outlines.
--
-- @since 0.19.2
module Unit.VersionCheckTest (tests) where

import qualified Canopy.Constraint as Constraint
import qualified Canopy.Details as Details
import qualified Canopy.Licenses as Licenses
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Test.Tasty
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  testGroup
    "Canopy.Details.VersionCheck"
    [ appVersionCheckTests,
      pkgVersionCheckTests,
      versionCheckShowTests
    ]

-- APP VERSION CHECK TESTS

appVersionCheckTests :: TestTree
appVersionCheckTests =
  testGroup
    "App version checking"
    [ HUnit.testCase "matching major.minor is VersionOk" $
        Details.checkCompilerVersion (Outline.App (appWithVersion Version.compiler))
          HUnit.@?= Details.VersionOk,
      HUnit.testCase "different patch version is still VersionOk" $
        let v = Version.bumpPatch Version.compiler
         in Details.checkCompilerVersion (Outline.App (appWithVersion v))
              HUnit.@?= Details.VersionOk,
      HUnit.testCase "different minor version is VersionMismatch" $
        let v = Version.bumpMinor Version.compiler
            result = Details.checkCompilerVersion (Outline.App (appWithVersion v))
         in case result of
              Details.VersionMismatch _ _ -> pure ()
              Details.VersionOk -> HUnit.assertFailure "Expected VersionMismatch for different minor",
      HUnit.testCase "different major version is VersionMismatch" $
        let v = Version.bumpMajor Version.compiler
            result = Details.checkCompilerVersion (Outline.App (appWithVersion v))
         in case result of
              Details.VersionMismatch _ _ -> pure ()
              Details.VersionOk -> HUnit.assertFailure "Expected VersionMismatch for different major",
      HUnit.testCase "mismatch contains required version string" $
        let v = Version.bumpMinor Version.compiler
            result = Details.checkCompilerVersion (Outline.App (appWithVersion v))
         in case result of
              Details.VersionMismatch required _ ->
                HUnit.assertBool "should contain required version" (required == Version.toChars v)
              Details.VersionOk -> HUnit.assertFailure "Expected VersionMismatch",
      HUnit.testCase "mismatch contains actual version string" $
        let v = Version.bumpMinor Version.compiler
            result = Details.checkCompilerVersion (Outline.App (appWithVersion v))
         in case result of
              Details.VersionMismatch _ actual ->
                HUnit.assertEqual "actual should be compiler version" (Version.toChars Version.compiler) actual
              Details.VersionOk -> HUnit.assertFailure "Expected VersionMismatch"
    ]

-- PKG VERSION CHECK TESTS

pkgVersionCheckTests :: TestTree
pkgVersionCheckTests =
  testGroup
    "Pkg version checking"
    [ HUnit.testCase "default canopy constraint is VersionOk" $
        Details.checkCompilerVersion (Outline.Pkg (pkgWithConstraint Constraint.defaultCanopy))
          HUnit.@?= Details.VersionOk,
      HUnit.testCase "anything constraint is VersionMismatch for pre-1.0 compiler" $
        case Details.checkCompilerVersion (Outline.Pkg (pkgWithConstraint Constraint.anything)) of
          Details.VersionMismatch _ _ -> pure ()
          Details.VersionOk -> HUnit.assertFailure "Expected VersionMismatch: anything requires >= 1.0.0",
      HUnit.testCase "exact match of compiler version is VersionOk" $
        Details.checkCompilerVersion (Outline.Pkg (pkgWithConstraint (Constraint.exactly Version.compiler)))
          HUnit.@?= Details.VersionOk,
      HUnit.testCase "future major version constraint is VersionMismatch" $
        let futureVer = Version.bumpMajor (Version.bumpMajor Version.compiler)
            constraint = Constraint.exactly futureVer
            result = Details.checkCompilerVersion (Outline.Pkg (pkgWithConstraint constraint))
         in case result of
              Details.VersionMismatch _ _ -> pure ()
              Details.VersionOk -> HUnit.assertFailure "Expected VersionMismatch for future constraint"
    ]

-- VERSION CHECK SHOW TESTS

versionCheckShowTests :: TestTree
versionCheckShowTests =
  testGroup
    "VersionCheck Show"
    [ HUnit.testCase "VersionOk shows correctly" $
        show Details.VersionOk HUnit.@?= "VersionOk",
      HUnit.testCase "VersionMismatch shows correctly" $
        show (Details.VersionMismatch "0.20.0" "0.19.1")
          HUnit.@?= "VersionMismatch \"0.20.0\" \"0.19.1\""
    ]

-- TEST FIXTURES

-- | Create an AppOutline with a specific Canopy version.
appWithVersion :: Version.Version -> Outline.AppOutline
appWithVersion ver =
  Outline.AppOutline
    { Outline._appCanopy = ver,
      Outline._appSrcDirs = [Outline.AbsoluteSrcDir "src"],
      Outline._appDeps = Map.empty,
      Outline._appTestDeps = Map.empty,
      Outline._appDepsDirect = Map.singleton Pkg.core Version.one,
      Outline._appDepsIndirect = Map.empty,
      Outline._appTestDepsDirect = Map.empty,
      Outline._appScripts = Nothing,
      Outline._appRepository = Nothing,
      Outline._appCapabilities = Set.empty
    }

-- | Create a PkgOutline with a specific Canopy constraint.
pkgWithConstraint :: Constraint.Constraint -> Outline.PkgOutline
pkgWithConstraint constraint =
  Outline.PkgOutline
    { Outline._pkgName = Pkg.core,
      Outline._pkgSummary = Outline.defaultSummary,
      Outline._pkgLicense = Licenses.bsd3,
      Outline._pkgVersion = Version.one,
      Outline._pkgExposed = Outline.ExposedList [],
      Outline._pkgDeps = Map.singleton Pkg.core Constraint.anything,
      Outline._pkgTestDeps = Map.empty,
      Outline._pkgCanopy = constraint
    }
