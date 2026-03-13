{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the ESM (ES Module) code generation backend.
--
-- Verifies the behavior of 'Generate.JavaScript.ESM.generate' and its
-- internal helper functions by constructing synthetic 'Opt.GlobalGraph'
-- and 'Mode.Mode' values and asserting on the resulting 'ESMOutput'.
--
-- Tests cover:
--
--   * Empty graph produces minimal, well-formed output
--   * Entry point generation with and without mains
--   * Runtime output structure (contains expected identifiers)
--   * Per-module file generation with import\/export scaffolding
--   * 'varToConst' transformation (Var → Const rewriting)
--   * Reachability analysis and dead-code exclusion
--
-- @since 0.20.0
module Unit.Generate.JavaScript.ESMTest (tests) where

import qualified AST.Optimized as Opt
import AST.Optimized.Expr (Expr (..), Global (..))
import qualified AST.Optimized.Graph as OptGraph
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.ESM as ESM
import Generate.JavaScript.ESM.Types (ESMOutput (..))
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

-- | All ESM generation tests.
tests :: TestTree
tests =
  Test.testGroup
    "Generate.JavaScript.ESM"
    [ emptyGraphTests,
      entryPointTests,
      runtimeTests,
      moduleGenerationTests,
      reachabilityTests,
      varToConstTests
    ]

-- EMPTY GRAPH TESTS

-- | Tests for generation from an empty global graph.
emptyGraphTests :: TestTree
emptyGraphTests =
  Test.testGroup
    "Empty graph"
    [ testCase "empty graph produces empty module map" $
        Map.null (_eoModules (generate emptyGraph emptyMains)) @?= True,
      testCase "empty graph produces empty FFI module map" $
        Map.null (_eoFFIModules (generate emptyGraph emptyMains)) @?= True,
      testCase "empty graph produces empty type defs map" $
        Map.null (_eoTypeDefs (generate emptyGraph emptyMains)) @?= True,
      testCase "empty graph runtime is non-empty" $
        assertBool "runtime should contain content" (builderLength (_eoRuntime (generate emptyGraph emptyMains)) > 0),
      testCase "empty graph entry point is the no-main sentinel" $
        builderToString (_eoEntry (generate emptyGraph emptyMains)) @?= "// No main functions found.\n"
    ]

-- ENTRY POINT TESTS

-- | Tests for entry point (@main.js@) generation.
entryPointTests :: TestTree
entryPointTests =
  Test.testGroup
    "Entry point generation"
    [ testCase "empty mains produces sentinel comment" $
        builderToString (_eoEntry (generate emptyGraph emptyMains))
          @?= "// No main functions found.\n",
      testCase "single main entry point includes runtime import" $
        assertBool
          "entry should import canopy-runtime.js"
          (containsSubstring "canopy-runtime.js" (builderToString (_eoEntry (generate emptyGraph singleMain)))),
      testCase "single main entry point includes entry comment" $
        assertBool
          "entry should contain Canopy application entry point comment"
          (containsSubstring "Canopy application entry point" (builderToString (_eoEntry (generate emptyGraph singleMain)))),
      testCase "single main entry point references module file" $
        assertBool
          "entry should reference the main module JS file"
          (containsSubstring "author.project.Main.js" (builderToString (_eoEntry (generate emptyGraph singleMain)))),
      testCase "single main entry point calls init function" $
        assertBool
          "entry should call a platform init function"
          (containsSubstring "_Platform_worker" (builderToString (_eoEntry (generate emptyGraph singleMain))))
    ]

-- RUNTIME TESTS

-- | Tests for the runtime module (@canopy-runtime.js@) output.
runtimeTests :: TestTree
runtimeTests =
  Test.testGroup
    "Runtime output"
    [ testCase "dev mode runtime is non-empty" $
        assertBool "dev runtime should have content" (builderLength devRuntime > 0),
      testCase "prod mode runtime is non-empty" $
        assertBool "prod runtime should have content" (builderLength prodRuntime > 0),
      testCase "dev runtime contains debug flag set to true" $
        assertBool
          "dev runtime should contain __canopy_debug = true"
          (containsSubstring "__canopy_debug" (builderToString devRuntime)),
      testCase "dev runtime exports canopy-runtime header comment" $
        assertBool
          "dev runtime should contain header comment"
          (containsSubstring "canopy-runtime.js" (builderToString devRuntime)),
      testCase "prod runtime contains debug flag" $
        assertBool
          "prod runtime should contain __canopy_debug"
          (containsSubstring "__canopy_debug" (builderToString prodRuntime))
    ]
  where
    devRuntime = _eoRuntime (generate emptyGraph emptyMains)
    prodRuntime = _eoRuntime (generateProd emptyGraph emptyMains)

-- MODULE GENERATION TESTS

-- | Tests for per-module ES module file generation.
moduleGenerationTests :: TestTree
moduleGenerationTests =
  Test.testGroup
    "Per-module generation"
    [ testCase "single reachable node produces one module file" $
        Map.size (_eoModules (generate singleNodeGraph singleMain)) @?= 1,
      testCase "generated module file is non-empty" $
        assertBool
          "module content should not be empty"
          (builderLength (head (Map.elems (_eoModules (generate singleNodeGraph singleMain)))) > 0),
      testCase "generated module imports canopy-runtime" $
        assertBool
          "module should import canopy-runtime.js"
          (containsSubstring "canopy-runtime.js" (moduleContent singleNodeGraph singleMain)),
      testCase "generated module contains header comment" $
        assertBool
          "module should contain auto-generated comment"
          (containsSubstring "Auto-generated by the Canopy compiler" (moduleContent singleNodeGraph singleMain)),
      testCase "two-module graph produces two module files" $
        Map.size (_eoModules (generate crossModuleGraph singleMain)) @?= 2,
      testCase "module with cross-module dep imports from dep module" $
        assertBool
          "module should import from its dependency"
          (containsSubstring "author.project.Helper.js" (moduleContent crossModuleGraph singleMain))
    ]

-- REACHABILITY TESTS

-- | Tests for reachability analysis and dead-code elimination.
reachabilityTests :: TestTree
reachabilityTests =
  Test.testGroup
    "Reachability analysis"
    [ testCase "dead node is not included in module output" $
        Map.notMember deadHome (_eoModules (generate graphWithDead singleMain)) @?= True,
      testCase "reachable node is included in module output" $
        Map.member testHome (_eoModules (generate graphWithDead singleMain)) @?= True,
      testCase "empty mains means no modules are generated" $
        Map.null (_eoModules (generate singleNodeGraph emptyMains)) @?= True
    ]

-- VAR-TO-CONST TRANSFORMATION TESTS

-- | Tests for 'varToConst', the Var → Const rewriting function.
--
-- This function is not exported but its effect is visible in generated output:
-- module-level declarations should use @const@ instead of @var@.
varToConstTests :: TestTree
varToConstTests =
  Test.testGroup
    "varToConst rewriting"
    [ testCase "generated Enum node uses const not var" $
        assertBool
          "enum declarations should use const in ESM output"
          (not (containsSubstring "\nvar " (moduleContent enumGraph singleMain))),
      testCase "generated module output contains const declarations" $
        assertBool
          "module output should contain const"
          (containsSubstring "const " (moduleContent singleNodeGraph singleMain))
    ]

-- HELPERS: Builders and extraction

-- | Render a 'Builder' to a 'String' for assertion comparison.
builderToString :: BB.Builder -> String
builderToString b =
  map (toEnum . fromEnum) (LBS.unpack (BB.toLazyByteString b))

-- | Return the byte length of a rendered 'Builder'.
builderLength :: BB.Builder -> Int
builderLength b =
  fromIntegral (LBS.length (BB.toLazyByteString b))

-- | Check whether a 'String' contains a given substring.
containsSubstring :: String -> String -> Bool
containsSubstring needle haystack =
  go haystack
  where
    nLen = length needle
    go [] = False
    go xs@(_ : rest)
      | take nLen xs == needle = True
      | otherwise = go rest

-- | Extract the content of the first module from generation output.
moduleContent :: Opt.GlobalGraph -> Map.Map ModuleName.Canonical Opt.Main -> String
moduleContent graph mains =
  case Map.elems (_eoModules (generate graph mains)) of
    [] -> ""
    (b : _) -> builderToString b

-- | Generate ESM output in dev mode.
generate :: Opt.GlobalGraph -> Map.Map ModuleName.Canonical Opt.Main -> ESMOutput
generate graph mains =
  ESM.generate devMode graph mains Map.empty

-- | Generate ESM output in prod mode.
generateProd :: Opt.GlobalGraph -> Map.Map ModuleName.Canonical Opt.Main -> ESMOutput
generateProd graph mains =
  ESM.generate prodMode graph mains Map.empty

-- HELPERS: Test data

testPkg :: Pkg.Name
testPkg = Pkg.Name (Utf8.fromChars "author") (Utf8.fromChars "project")

testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical testPkg (Name.fromChars "Main")

helperHome :: ModuleName.Canonical
helperHome = ModuleName.Canonical testPkg (Name.fromChars "Helper")

deadHome :: ModuleName.Canonical
deadHome = ModuleName.Canonical testPkg (Name.fromChars "Dead")

mainGlobal :: Global
mainGlobal = Global testHome (Name.fromChars "main")

helperGlobal :: Global
helperGlobal = Global helperHome (Name.fromChars "helper")

deadGlobal :: Global
deadGlobal = Global deadHome (Name.fromChars "dead")

-- | A minimal expression for building test graph nodes.
simpleExpr :: Expr
simpleExpr = Bool True

-- | Build an 'Opt.GlobalGraph' from a list of (Global, Node) pairs.
mkGraph :: [(Global, OptGraph.Node)] -> Opt.GlobalGraph
mkGraph entries =
  OptGraph.GlobalGraph (Map.fromList entries) Map.empty Map.empty

emptyGraph :: Opt.GlobalGraph
emptyGraph = mkGraph []

emptyMains :: Map.Map ModuleName.Canonical Opt.Main
emptyMains = Map.empty

singleMain :: Map.Map ModuleName.Canonical Opt.Main
singleMain = Map.singleton testHome Opt.Static

-- | Graph with a single main node that has no dependencies.
singleNodeGraph :: Opt.GlobalGraph
singleNodeGraph =
  mkGraph [(mainGlobal, OptGraph.Define simpleExpr Set.empty)]

-- | Graph where main depends on a helper in a different module.
crossModuleGraph :: Opt.GlobalGraph
crossModuleGraph =
  mkGraph
    [ (mainGlobal, OptGraph.Define simpleExpr (Set.singleton helperGlobal)),
      (helperGlobal, OptGraph.Define simpleExpr Set.empty)
    ]

-- | Graph with a reachable main and an unreachable dead node.
graphWithDead :: Opt.GlobalGraph
graphWithDead =
  mkGraph
    [ (mainGlobal, OptGraph.Define simpleExpr Set.empty),
      (deadGlobal, OptGraph.Define simpleExpr Set.empty)
    ]

-- | Graph with an Enum node to verify varToConst rewriting.
enumGlobal :: Global
enumGlobal = Global testHome (Name.fromChars "MyEnum")

enumGraph :: Opt.GlobalGraph
enumGraph =
  mkGraph
    [ (mainGlobal, OptGraph.Define simpleExpr (Set.singleton enumGlobal)),
      (enumGlobal, OptGraph.Enum Index.first)
    ]

devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

prodMode :: Mode.Mode
prodMode = Mode.Prod Map.empty False False False StringPool.emptyPool Set.empty
