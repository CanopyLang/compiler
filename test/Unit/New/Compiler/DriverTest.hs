
-- | Tests for the new query-based compiler driver.
--
-- @since 0.19.1
module Unit.New.Compiler.DriverTest (tests) where

import qualified Canopy.Interface as I
import qualified Canopy.Package as Pkg
import qualified Data.Map as Map
import qualified Driver
import qualified PackageCache
import qualified Parse.Module as Parse
import qualified System.IO as IO
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase)

tests :: TestTree
tests =
  testGroup
    "New.Compiler.Driver"
    [ testGroup
        "compileModule"
        [ testCase "compiles simple module" testSimpleModule
        ]
    ]

-- | Test compiling a simple module without imports.
--
-- Creates a minimal valid Canopy module, compiles it through the full
-- pipeline (parse, canonicalize, type check, optimize), and verifies
-- that no errors are produced.
testSimpleModule :: IO ()
testSimpleModule = do
  -- Load elm/core interfaces for Basics, List, etc.
  maybeCoreIfaces <- PackageCache.loadElmCoreInterfaces
  case maybeCoreIfaces of
    Nothing ->
      assertFailure "elm/core not installed - run 'elm install elm/core' first"
    Just depIfaces -> do
      -- Convert DependencyInterface to Interface for compilation
      let ifaces = Map.map extractPublicInterface depIfaces

      -- Write a minimal valid Canopy module to a temporary file.
      -- The module is intentionally empty (no declarations) to avoid
      -- dependency on any standard library functions.
      let testFile = "/tmp/test-minimal.can"
      IO.writeFile testFile minimalModuleSource

      let pkg = Pkg.core
      let projectType = Parse.Package pkg

      result <- Driver.compileModule pkg ifaces testFile projectType

      case result of
        Left err ->
          assertBool
            ("Expected successful compilation, got error: " ++ show err)
            False
        Right _compileResult ->
          assertBool "Module compiled successfully" True
  where
    -- Minimal valid Canopy module with a single custom type declaration.
    -- The custom type has no dependencies on any imported modules, making
    -- it safe to compile without default imports (as required for Package
    -- project types where isCore = True).
    minimalModuleSource :: String
    minimalModuleSource =
      unlines
        [ "module CanopyTest exposing (..)"
        , ""
        , "type MinimalType = MinimalType"
        ]

    -- Extract public interface from dependency interface
    extractPublicInterface :: I.DependencyInterface -> I.Interface
    extractPublicInterface (I.Public iface) = iface
    extractPublicInterface (I.Private pkg unions aliases) =
      -- Create minimal interface from private data
      I.Interface
        { I._home = pkg
        , I._values = Map.empty
        , I._unions = Map.map I.PrivateUnion unions
        , I._aliases = Map.map I.PrivateAlias aliases
        , I._binops = Map.empty
        }
