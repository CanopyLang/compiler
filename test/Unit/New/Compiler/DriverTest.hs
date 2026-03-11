
-- | Tests for the new query-based compiler driver.
--
-- @since 0.19.1
module Unit.New.Compiler.DriverTest (tests) where

import qualified Canopy.Interface as Interface
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
  -- Load core interfaces for Basics, List, etc.
  maybeCoreIfaces <- PackageCache.loadElmCoreInterfaces
  case maybeCoreIfaces of
    Nothing ->
      assertFailure "core not installed - run 'canopy install canopy/core' first"
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
    extractPublicInterface :: Interface.DependencyInterface -> Interface.Interface
    extractPublicInterface (Interface.Public iface) = iface
    extractPublicInterface (Interface.Private pkg unions aliases) =
      -- Create minimal interface from private data
      Interface.Interface
        { Interface._home = pkg
        , Interface._values = Map.empty
        , Interface._unions = Map.map Interface.PrivateUnion unions
        , Interface._aliases = Map.map Interface.PrivateAlias aliases
        , Interface._binops = Map.empty
        , Interface._ifaceGuards = Map.empty
        , Interface._ifaceAbilities = Map.empty
        , Interface._ifaceImpls = []
        }
