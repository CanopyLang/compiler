{-# LANGUAGE OverloadedStrings #-}

-- | Tests that TEA effect-manager glue survives reachability analysis.
--
-- An @Opt.Manager@ node carries no dependencies of its own, yet the JS emitter
-- ('Generate.JavaScript.Kernel.generateManagerHelp', the source of truth) generates
-- and recurses into the manager's @init@/@onEffects@/@onSelfMsg@ functions plus
-- @cmdMap@ and/or @subMap@. Both reachability walks must mirror that emission:
--
--   * 'Generate.TreeShake.reachableGlobals' drives the @--optimize@ FFI tree-shaker;
--     if it drops the manager fns then their FFI bindings vanish and the bundle
--     throws \"Cannot read property 'a' of undefined\" at the first Cmd/Sub.
--   * 'Generate.JavaScript.CodeSplit.Analyze.reachableFrom' gates code-split EMISSION;
--     a manager fn absent from a chunk's globals is never emitted.
--
-- The fn-name knowledge now lives in ONE shared exported function
-- 'Generate.TreeShake.managerFnDeps'; the final \"drift guard\" case asserts both
-- walks therefore agree.
--
-- == Test Coverage
--
-- * For Cmd/Sub/Fx managers: every generated fn reached only through the manager
--   node survives tree-shaking.
-- * An FFI-binding 'Opt.Define' reached only via @onEffects@ survives (the exact
--   regression the reachability fix targets).
-- * The code-split walk keeps the same fns, including when the manager sits behind
--   a lazy import boundary (its fns land in the lazy chunk, not dropped).
-- * Drift guard: TreeShake and Analyze report identical manager-fn sets.
--
-- @since 0.20.0
module Unit.Generate.ManagerReachabilityTest (tests) where

import AST.Optimized.Expr (Expr (..), Global (..))
import qualified AST.Optimized.Graph as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens ((^.))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generate.JavaScript.CodeSplit.Analyze (analyze, reachableFrom)
import Generate.JavaScript.CodeSplit.Types
  ( ChunkKind (..),
    SplitConfig (..),
    cgEntry,
    cgGlobalToChunk,
    cgLazy,
    chunkGlobals,
    chunkKind,
  )
import Generate.TreeShake (managerFnDeps, reachableGlobals)
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Generate.ManagerReachability"
    [ treeShakeManagerTests,
      ffiBindingSurvivalTests,
      codeSplitManagerTests,
      driftGuardTests
    ]

-- TREE-SHAKING: manager fns reached only through the Manager node survive.

treeShakeManagerTests :: TestTree
treeShakeManagerTests =
  Test.testGroup
    "TreeShake keeps manager glue"
    [ Test.testCase "Cmd manager: init/onEffects/onSelfMsg/cmdMap all reachable" $
        assertAllReachable Opt.Cmd cmdFns,
      Test.testCase "Sub manager: init/onEffects/onSelfMsg/subMap all reachable" $
        assertAllReachable Opt.Sub subFns,
      Test.testCase "Fx manager: init/onEffects/onSelfMsg/cmdMap/subMap all reachable" $
        assertAllReachable Opt.Fx fxFns,
      Test.testCase "Cmd manager pulls in exactly its four fns (none dropped)" $
        let reached = reachableGlobals (managerGraph Opt.Cmd) singleMain
            expected = Set.fromList (map managerGlobal cmdFns)
         in Set.intersection reached expected @?= expected
    ]
  where
    assertAllReachable et fns =
      let reached = reachableGlobals (managerGraph et) singleMain
       in mapM_
            (\fn -> Set.member (managerGlobal fn) reached @?= True)
            fns

-- REGRESSION: an FFI binding reached ONLY via onEffects survives tree-shaking.
--
-- This is the precise failure the reachability fix targets: under --optimize the
-- FFI tree-shaker drops anything the manager fns reach, so the runtime FFI binding
-- (here 'ffiBindingGlobal', a stand-in for Native.Module.callStreaming) disappears
-- and the bundle throws at the first effect.

ffiBindingSurvivalTests :: TestTree
ffiBindingSurvivalTests =
  Test.testGroup
    "FFI binding reached only through onEffects survives"
    [ Test.testCase "TreeShake keeps the FFI binding under the manager" $
        Set.member ffiBindingGlobal (reachableGlobals ffiGraph singleMain) @?= True,
      Test.testCase "onEffects itself is reachable (its dep edge is followed)" $
        Set.member (managerGlobal "onEffects") (reachableGlobals ffiGraph singleMain) @?= True,
      Test.testCase "code-split walk also keeps the FFI binding" $
        Set.member ffiBindingGlobal (reachableFrom (rawGraph ffiGraph) (Set.singleton mainGlobal)) @?= True
    ]

-- CODE-SPLIT: Analyze.reachableFrom keeps manager fns; analyze places them in a chunk.

codeSplitManagerTests :: TestTree
codeSplitManagerTests =
  Test.testGroup
    "Analyze keeps manager glue"
    [ Test.testCase "reachableFrom keeps all Cmd manager fns" $
        let reached = reachableFrom (rawGraph (managerGraph Opt.Cmd)) (Set.singleton mainGlobal)
         in mapM_ (\fn -> Set.member (managerGlobal fn) reached @?= True) cmdFns,
      Test.testCase "reachableFrom keeps all Fx manager fns" $
        let reached = reachableFrom (rawGraph (managerGraph Opt.Fx)) (Set.singleton mainGlobal)
         in mapM_ (\fn -> Set.member (managerGlobal fn) reached @?= True) fxFns,
      Test.testCase "manager behind a lazy boundary: fns land in the lazy chunk" $
        let cg = analyze lazyManagerConfig (managerGraph Opt.Fx) singleMain
            lazyGlobals = Set.unions (map (^. chunkGlobals) (cg ^. cgLazy))
         in mapM_ (\fn -> Set.member (managerGlobal fn) lazyGlobals @?= True) fxFns,
      Test.testCase "lazy chunk for the manager module has LazyChunk kind" $
        let cg = analyze lazyManagerConfig (managerGraph Opt.Fx) singleMain
         in case cg ^. cgLazy of
              [chunk] -> (chunk ^. chunkKind) @?= LazyChunk
              _ -> Test.assertFailure "expected exactly one lazy chunk for the manager module",
      Test.testCase "manager fns are NOT left orphaned in entry when lazy" $
        let cg = analyze lazyManagerConfig (managerGraph Opt.Fx) singleMain
            entryGlobals = cg ^. cgEntry . chunkGlobals
         in mapM_ (\fn -> Set.member (managerGlobal fn) entryGlobals @?= False) fxFns,
      Test.testCase "every manager fn is assigned to some chunk" $
        let cg = analyze lazyManagerConfig (managerGraph Opt.Fx) singleMain
            globalMap = cg ^. cgGlobalToChunk
         in mapM_ (\fn -> Map.member (managerGlobal fn) globalMap @?= True) fxFns
    ]

-- DRIFT GUARD: both walks route through the one shared managerFnDeps, so the
-- manager-fn set they each report must be identical.

driftGuardTests :: TestTree
driftGuardTests =
  Test.testGroup
    "TreeShake and Analyze agree (no drift)"
    [ Test.testCase "Cmd: TreeShake and Analyze report the same manager fns" $
        sameManagerFns Opt.Cmd cmdFns,
      Test.testCase "Sub: TreeShake and Analyze report the same manager fns" $
        sameManagerFns Opt.Sub subFns,
      Test.testCase "Fx: TreeShake and Analyze report the same manager fns" $
        sameManagerFns Opt.Fx fxFns,
      Test.testCase "shared managerFnDeps Cmd is exactly its four fns" $
        managerFnDeps managerHome Opt.Cmd @?= Set.fromList (map managerGlobal cmdFns),
      Test.testCase "shared managerFnDeps Fx is exactly its five fns" $
        managerFnDeps managerHome Opt.Fx @?= Set.fromList (map managerGlobal fxFns)
    ]
  where
    -- Intersecting each walk's full reachable set with the manager-fn universe
    -- isolates exactly the fns each walk attributes to the Manager node.
    sameManagerFns et fns =
      let universe = Set.fromList (map managerGlobal fns)
          fromTreeShake =
            Set.intersection universe (reachableGlobals (managerGraph et) singleMain)
          fromAnalyze =
            Set.intersection
              universe
              (reachableFrom (rawGraph (managerGraph et)) (Set.singleton mainGlobal))
       in do
            fromTreeShake @?= universe
            fromAnalyze @?= universe
            fromTreeShake @?= fromAnalyze

-- HELPERS: module names, globals, and graph construction.

testPackage :: Pkg.Name
testPackage = Pkg.core

-- | Home of @main@ (the entry point).
mainHome :: ModuleName.Canonical
mainHome = ModuleName.Canonical testPackage (Name.fromChars "Main")

-- | Home of the effect manager and its generated fns.
managerHome :: ModuleName.Canonical
managerHome = ModuleName.Canonical testPackage (Name.fromChars "Effect.Manager")

mainGlobal :: Global
mainGlobal = Global mainHome (Name.fromChars "main")

-- | The manager node itself (the value @main@ depends on).
managerNodeGlobal :: Global
managerNodeGlobal = Global managerHome (Name.fromChars "manager")

-- | A generated manager fn global (init/onEffects/...) in the manager's home.
managerGlobal :: String -> Global
managerGlobal name = Global managerHome (Name.fromChars name)

-- | A stand-in FFI runtime binding (e.g. Native.Module.callStreaming) reached only
-- through the manager's @onEffects@.
ffiBindingGlobal :: Global
ffiBindingGlobal = Global managerHome (Name.fromChars "callStreaming")

cmdFns :: [String]
cmdFns = ["init", "onEffects", "onSelfMsg", "cmdMap"]

subFns :: [String]
subFns = ["init", "onEffects", "onSelfMsg", "subMap"]

fxFns :: [String]
fxFns = ["init", "onEffects", "onSelfMsg", "cmdMap", "subMap"]

simpleExpr :: Expr
simpleExpr = Bool True

singleMain :: Map ModuleName.Canonical Opt.Main
singleMain = Map.singleton mainHome Opt.Static

-- | Config that marks the manager's module as a lazy import boundary.
lazyManagerConfig :: SplitConfig
lazyManagerConfig = SplitConfig (Set.singleton managerHome) 2

mkGraph :: [(Global, Opt.Node)] -> Opt.GlobalGraph
mkGraph entries =
  Opt.GlobalGraph (Map.fromList entries) Map.empty Map.empty

-- | The raw node map used by 'Analyze.reachableFrom' / 'analyze' (the 'GlobalGraph'
-- field), as opposed to the 'GlobalGraph' wrapper 'reachableGlobals' consumes.
rawGraph :: Opt.GlobalGraph -> Map Global Opt.Node
rawGraph (Opt.GlobalGraph nodes _ _) = nodes

-- | Graph where @main@ depends on a Manager node of the given kind, plus a 'Define'
-- stub for every fn the JS emitter generates for that manager kind. The fn stubs are
-- reachable ONLY through the Manager node (nothing else references them), so they
-- survive iff the reachability walk mirrors the emitter.
managerGraph :: Opt.EffectsType -> Opt.GlobalGraph
managerGraph effectsType =
  mkGraph (mainEntry : managerEntry : fnStubs)
  where
    fns = case effectsType of
      Opt.Cmd -> cmdFns
      Opt.Sub -> subFns
      Opt.Fx -> fxFns
    mainEntry = (mainGlobal, Opt.Define simpleExpr (Set.singleton managerNodeGlobal))
    managerEntry = (managerNodeGlobal, Opt.Manager effectsType)
    fnStubs = [(managerGlobal fn, Opt.Define simpleExpr Set.empty) | fn <- fns]

-- | Like 'managerGraph' for a Cmd manager, but @onEffects@ additionally depends on a
-- runtime FFI binding ('ffiBindingGlobal') reached through no other path. Exercises
-- the real-world failure: the FFI binding is dropped unless onEffects is kept.
ffiGraph :: Opt.GlobalGraph
ffiGraph =
  mkGraph
    ( [ (mainGlobal, Opt.Define simpleExpr (Set.singleton managerNodeGlobal)),
        (managerNodeGlobal, Opt.Manager Opt.Cmd),
        (managerGlobal "onEffects", Opt.Define simpleExpr (Set.singleton ffiBindingGlobal)),
        (ffiBindingGlobal, Opt.Define simpleExpr Set.empty)
      ]
        ++ [ (managerGlobal fn, Opt.Define simpleExpr Set.empty)
           | fn <- cmdFns,
             fn /= "onEffects"
           ]
    )
