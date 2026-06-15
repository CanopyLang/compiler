-- | Tests for 'PackageCache.resolveInstalledVersion'.
--
-- The resolver scans the installed package cache (@~\/.canopy\/packages@ and
-- @~\/.elm\/0.19.1\/packages@) and picks the highest installed version that
-- satisfies a dependency constraint, instead of collapsing every constraint to
-- its lower bound. This is what lets package/test builds pick up a @canopy
-- link@ed HEAD version while a clean offline build still falls back to a
-- definite lower-bound target.
--
-- 'PackageCache.resolveInstalledVersion' reads the real @$HOME@, so for testing these
-- assertions use its injectable sibling 'PackageCache.resolveInstalledVersionIn', which
-- takes the cache root as an explicit argument. Each test builds a fake cache under a
-- 'withSystemTempDirectory' path and passes that path as the root — mutating NO
-- process-global state ($HOME is left untouched), so the tests are safe to run in
-- parallel with everything else under tasty's scheduler.
--
-- @since 0.19.2
module Unit.Builder.PackageCache.ResolveTest (tests) where

import qualified Canopy.Constraint as Constraint
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import Control.Exception (SomeException, try)
import Control.Monad (forM_)
import Data.List (isInfixOf)
import qualified PackageCache
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  -- 'resolveInstalledVersionIn' takes the cache root explicitly, so these assertions
  -- mutate no process-global state and need no sequencing — plain parallel testGroup.
  testGroup
    "PackageCache.resolveInstalledVersion"
    [ testHighestSatisfyingWins,
      testConstraintFiltersOutOfRange,
      testPrimaryBeatsHigherFallback,
      testFallbackOnlyIsReturned,
      testEmptyCacheFallsBackToLowerBound,
      testMissingForkPackageErrorsLoudly,
      testForkPackageIgnoresElmFallback,
      testForkPackageResolvesFromOwnAuthor
    ]

-- HELPERS -------------------------------------------------------------------

-- | The Canopy package cache root under a fake HOME.
canopyRoot :: FilePath -> FilePath
canopyRoot home = home </> ".canopy" </> "packages"

-- | The Elm-compat package cache root under a fake HOME.
elmRoot :: FilePath -> FilePath
elmRoot home = home </> ".elm" </> "0.19.1" </> "packages"

-- | Build a @Pkg.Name@ from author\/project strings.
mkName :: String -> String -> Pkg.Name
mkName author project =
  Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

ver :: String -> Version.Version
ver s = case Version.fromChars s of
  Just v -> v
  Nothing -> error ("ResolveTest: bad version literal " ++ s)

-- | The standard @1.0.0 <= v < 2.0.0@ range used across the assertions.
caretConstraint :: Constraint.Constraint
caretConstraint = case Constraint.fromChars "1.0.0 <= v < 2.0.0" of
  Just c -> c
  Nothing -> error "ResolveTest: failed to parse caretConstraint"

-- | Create an empty installed-version directory @root\/author\/project\/version@.
-- 'PackageCache.installedVersionsTagged' only inspects the directory NAME to
-- parse the version, so no files are needed inside it.
installVersion :: FilePath -> String -> String -> String -> IO ()
installVersion root author project version =
  createDirectoryIfMissing True (root </> author </> project </> version)

-- | Run an action with a fresh temp directory as the package-cache root, handed
-- explicitly to 'PackageCache.resolveInstalledVersionIn'. Unlike pointing @$HOME@ at the
-- temp dir, this mutates NO process-global state, so these tests are safe to run
-- concurrently with any other test that reads @$HOME@. The temp dir is removed by
-- 'withSystemTempDirectory'.
withTempCacheRoot :: (FilePath -> IO a) -> IO a
withTempCacheRoot = withSystemTempDirectory "canopy-resolve-test"

-- ASSERTIONS ----------------------------------------------------------------

-- (1) Highest-satisfying version installed under the package's own author wins.
testHighestSatisfyingWins :: TestTree
testHighestSatisfyingWins =
  testCase "highest satisfying version wins" $
    withTempCacheRoot $ \home -> do
      let name = mkName "canopy" "virtual-dom"
      forM_ ["1.0.3", "1.0.4", "1.0.5"] $ \v ->
        installVersion (canopyRoot home) "canopy" "virtual-dom" v
      resolved <- PackageCache.resolveInstalledVersionIn home name caretConstraint
      resolved @?= ver "1.0.5"

-- (1b) Versions outside the constraint are excluded; the highest *satisfying*
-- one wins even when a higher non-satisfying version is also installed.
testConstraintFiltersOutOfRange :: TestTree
testConstraintFiltersOutOfRange =
  testCase "out-of-range versions are filtered out" $
    withTempCacheRoot $ \home -> do
      let name = mkName "canopy" "core"
      -- 2.0.1 is installed but violates `v < 2.0.0`; 1.9.9 is the max in-range.
      forM_ ["1.0.0", "1.9.9", "2.0.1"] $ \v ->
        installVersion (canopyRoot home) "canopy" "core" v
      resolved <- PackageCache.resolveInstalledVersionIn home name caretConstraint
      resolved @?= ver "1.9.9"

-- (2) A version under the package's OWN author beats a HIGHER version that only
-- exists via the canopy<->elm fallback author. fallbackAuthor "elm" == "canopy",
-- so for name elm/X the primary dir is elm/X and the fallback dir is canopy/X.
-- The resolver returns max(primary) whenever primary is non-empty, even if a
-- fallback copy is strictly higher.
testPrimaryBeatsHigherFallback :: TestTree
testPrimaryBeatsHigherFallback =
  testCase "primary author wins over a higher fallback-only version" $
    withTempCacheRoot $ \home -> do
      let name = mkName "elm" "html"
      -- primary (elm/html): 1.0.5 ; fallback (canopy/html): 1.0.9
      installVersion (canopyRoot home) "elm" "html" "1.0.5"
      installVersion (canopyRoot home) "canopy" "html" "1.0.9"
      resolved <- PackageCache.resolveInstalledVersionIn home name caretConstraint
      resolved @?= ver "1.0.5"

-- (2b) When ONLY a fallback copy exists, it is still returned.
testFallbackOnlyIsReturned :: TestTree
testFallbackOnlyIsReturned =
  testCase "fallback-only version is returned when no primary exists" $
    withTempCacheRoot $ \home -> do
      let name = mkName "elm" "json"
      -- nothing under elm/json; only canopy/json (the fallback author) present.
      installVersion (elmRoot home) "canopy" "json" "1.1.3"
      resolved <- PackageCache.resolveInstalledVersionIn home name caretConstraint
      resolved @?= ver "1.1.3"

-- (3) An empty cache resolves to the constraint's lower bound, preserving the
-- offline clean-build fallback.
testEmptyCacheFallsBackToLowerBound :: TestTree
testEmptyCacheFallsBackToLowerBound =
  testCase "empty cache falls back to the constraint lower bound" $
    withTempCacheRoot $ \home -> do
      let name = mkName "canopy" "not-installed"
      resolved <- PackageCache.resolveInstalledVersionIn home name caretConstraint
      resolved @?= Constraint.lowerBound caretConstraint
      resolved @?= ver "1.0.0"

-- (4) For the genuinely-forked FFI set ({core, virtual-dom, html, json}) a missing
-- install is a LOUD resolve-time error, NOT a silent lower-bound fallback into the
-- FFI-less elm namesake. This is the hardening that converts the cryptic gen-time
-- "Missing global VirtualDomFFI.init" into an actionable resolve-time message.
testMissingForkPackageErrorsLoudly :: TestTree
testMissingForkPackageErrorsLoudly =
  testCase "missing canopy fork package errors loudly (no silent elm fallback)" $
    withTempCacheRoot $ \home -> do
      let name = mkName "canopy" "virtual-dom"
      -- Nothing is installed under canopy/virtual-dom; an elm/virtual-dom copy exists
      -- but must NOT be used to satisfy the fork package.
      installVersion (elmRoot home) "elm" "virtual-dom" "1.0.5"
      result <- try (PackageCache.resolveInstalledVersionIn home name caretConstraint)
      case (result :: Either SomeException Version.Version) of
        Right v ->
          assertFailure ("expected a loud error, but resolved to " ++ Version.toChars v)
        Left e ->
          assertBool
            ("error message should name the missing package; got: " ++ show e)
            ("canopy/virtual-dom" `isInfixOf` show e)

-- (5) Even when an elm/<fork> copy is the only thing in the cache, a canopy/<fork>
-- request never silently degrades to it — the canopy->elm fallback DIRECTION is dropped
-- for fork packages. (Pairs with (4): here we assert it does not resolve.)
testForkPackageIgnoresElmFallback :: TestTree
testForkPackageIgnoresElmFallback =
  testCase "canopy fork package ignores an elm fallback copy" $
    withTempCacheRoot $ \home -> do
      let name = mkName "canopy" "html"
      -- elm/html is present (the FFI-less namesake) but canopy/html is not.
      installVersion (elmRoot home) "elm" "html" "1.0.1"
      installVersion (canopyRoot home) "elm" "html" "1.0.1"
      result <- try (PackageCache.resolveInstalledVersionIn home name caretConstraint)
      case (result :: Either SomeException Version.Version) of
        Right v -> assertFailure ("fork package must not resolve via elm fallback; got " ++ Version.toChars v)
        Left _ -> pure ()

-- (6) A fork package DOES resolve when installed under its own (canopy) author.
testForkPackageResolvesFromOwnAuthor :: TestTree
testForkPackageResolvesFromOwnAuthor =
  testCase "canopy fork package resolves from its own author" $
    withTempCacheRoot $ \home -> do
      let name = mkName "canopy" "core"
      forM_ ["1.0.5", "1.1.0"] $ \v ->
        installVersion (canopyRoot home) "canopy" "core" v
      resolved <- PackageCache.resolveInstalledVersionIn home name caretConstraint
      resolved @?= ver "1.1.0"
