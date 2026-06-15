-- | Cross-consistency property between the @canopy init@ and @canopy setup@ scaffolds.
--
-- @New.canopyJsonContent AppTemplate@ (the @canopy.json@ written by @canopy init@)
-- declares each canopy/* dependency as a SemVer RANGE, while @Setup.standardPackages@
-- (the versions @canopy setup@ pre-fetches) lists the concrete version of each. If they
-- drift apart — a package the scaffold declares is missing from Setup, or Setup's
-- pre-fetched version does not SATISFY the scaffold's range — a freshly scaffolded
-- project declares a dependency it never installs.
--
-- These assertions encode that as a PROPERTY (no hardcoded version literals to bump):
-- every canopy/* dep in the scaffold appears in Setup, and Setup's version satisfies the
-- scaffold's range. A future version bump touches only New.hs + Setup.hs, never this test.
--
-- @since 0.19.2
module Unit.Terminal.ScaffoldVersionGolden (tests) where

import qualified Canopy.Constraint as Constraint
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Data.List (isPrefixOf, stripPrefix)
import Data.Maybe (mapMaybe)
import qualified New
import qualified Setup
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "scaffold version consistency (New.hs / Setup.hs)"
    [ testScaffoldDeclaresRanges,
      testEveryScaffoldDepIsInSetup,
      testSetupSatisfiesScaffoldRange
    ]

-- | Each canopy/* dependency the @canopy init@ scaffold declares, as
-- @("canopy/<project>", <constraint>)@, extracted from the generated @canopy.json@.
scaffoldDeps :: [(String, Constraint.Constraint)]
scaffoldDeps =
  mapMaybe parseLine (lines (New.canopyJsonContent New.AppTemplate))
  where
    -- Lines look like:  "            \"canopy/core\": \"1.0.0 <= v < 2.0.0\","
    parseLine raw =
      let t = trim raw
       in if "\"canopy/" `isPrefixOf` t
            then do
              afterName <- stripPrefix "\"" t
              let (name, rest0) = break (== '"') afterName
              rest1 <- stripPrefix "\":" rest0
              let rest2 = dropWhile (`elem` [' ', '\t']) rest1
              spec <- takeQuoted rest2
              c <- Constraint.fromChars spec
              pure (name, c)
            else Nothing

    takeQuoted s = do
      afterOpen <- stripPrefix "\"" s
      pure (takeWhile (/= '"') afterOpen)

    trim = dropWhile (`elem` [' ', '\t'])

-- | The standard packages @canopy setup@ pre-fetches, keyed by "author/project".
setupVersions :: [(String, Version.Version)]
setupVersions = [(Pkg.toChars n, v) | (n, v) <- Setup.standardPackages]

-- | Sanity: the scaffold must actually parse into at least one canopy/* dep, and they
-- must be ranges (not bare exact pins) so fresh apps float to the latest installed.
testScaffoldDeclaresRanges :: TestTree
testScaffoldDeclaresRanges =
  testCase "canopy init scaffold declares canopy/* deps as parseable ranges" $ do
    assertBool "scaffold should declare at least one canopy/* dependency" (not (null scaffoldDeps))
    mapM_ assertIsMajorRange scaffoldDeps
  where
    -- A floating range admits more than its lower bound (i.e. it is not an exact
    -- "x <= v <= x" pin), so the scaffold genuinely floats canopy/* deps.
    assertIsMajorRange (name, c) =
      assertBool
        (name ++ " should be a floating range, not an exact pin (" ++ Constraint.toChars c ++ ")")
        (c /= Constraint.exactly (Constraint.lowerBound c))

-- | Every canopy/* dep the scaffold declares is present in Setup.standardPackages.
testEveryScaffoldDepIsInSetup :: TestTree
testEveryScaffoldDepIsInSetup =
  testCase "every canopy/* scaffold dep is pre-fetched by canopy setup" $
    mapM_ assertInSetup scaffoldDeps
  where
    assertInSetup (name, _) =
      case lookup name setupVersions of
        Just _ -> pure ()
        Nothing -> assertFailure (name ++ " is declared in the scaffold but missing from Setup.standardPackages")

-- | The version Setup pre-fetches for each scaffold dep SATISFIES the scaffold's range,
-- so a freshly scaffolded project's range is satisfiable from what setup installs.
testSetupSatisfiesScaffoldRange :: TestTree
testSetupSatisfiesScaffoldRange =
  testCase "Setup version satisfies the scaffold's declared range" $
    mapM_ assertSatisfies scaffoldDeps
  where
    assertSatisfies (name, c) =
      case lookup name setupVersions of
        Nothing -> assertFailure (name ++ " missing from Setup.standardPackages")
        Just v ->
          assertBool
            ( name
                ++ ": Setup version "
                ++ Version.toChars v
                ++ " does not satisfy scaffold range "
                ++ Constraint.toChars c
            )
            (Constraint.satisfies c v)
