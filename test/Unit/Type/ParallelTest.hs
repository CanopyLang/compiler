{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Type.Parallel module.
--
-- Tests the InterfaceStore, check-level computation, and
-- concurrent type-check-level execution.
--
-- @since 0.19.2
module Unit.Type.ParallelTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Test.Tasty
import Test.Tasty.HUnit
import qualified Type.Parallel as Parallel

tests :: TestTree
tests =
  testGroup
    "Type.Parallel Tests"
    [ testInterfaceStore,
      testComputeCheckLevels,
      testTypeCheckLevel
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- InterfaceStore
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testInterfaceStore :: TestTree
testInterfaceStore =
  testGroup
    "InterfaceStore"
    [ testCase "new store is empty" $ do
        store <- Parallel.newInterfaceStore
        ifaces <- Parallel.storedInterfaces store
        Map.size ifaces @?= 0,
      testCase "store and retrieve interface" $ do
        store <- Parallel.newInterfaceStore
        Parallel.storeInterface store mainName testInterface
        result <- Parallel.lookupInterface store mainName
        assertJust "Expected to find stored interface" result,
      testCase "lookup missing module returns Nothing" $ do
        store <- Parallel.newInterfaceStore
        result <- Parallel.lookupInterface store mainName
        result @?= Nothing,
      testCase "store multiple interfaces" $ do
        store <- Parallel.newInterfaceStore
        Parallel.storeInterface store mainName testInterface
        Parallel.storeInterface store utilsName testInterface
        ifaces <- Parallel.storedInterfaces store
        Map.size ifaces @?= 2,
      testCase "overwrite existing interface" $ do
        store <- Parallel.newInterfaceStore
        Parallel.storeInterface store mainName testInterface
        Parallel.storeInterface store mainName testInterface
        ifaces <- Parallel.storedInterfaces store
        Map.size ifaces @?= 1
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- computeCheckLevels
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testComputeCheckLevels :: TestTree
testComputeCheckLevels =
  testGroup
    "computeCheckLevels"
    [ testCase "empty dependency map yields no levels" $ do
        let levels = Parallel.computeCheckLevels Map.empty
        levels @?= [],
      testCase "single module with no deps is level 0" $ do
        let deps = Map.singleton mainName Set.empty
            levels = Parallel.computeCheckLevels deps
        length levels @?= 1
        extractModules levels @?= [[mainName]],
      testCase "independent modules are in same level" $ do
        let deps =
              Map.fromList
                [ (mainName, Set.empty),
                  (utilsName, Set.empty)
                ]
            levels = Parallel.computeCheckLevels deps
        length levels @?= 1
        length (concatMap Parallel._levelModules levels) @?= 2,
      testCase "dependent module is in later level" $ do
        let deps =
              Map.fromList
                [ (utilsName, Set.empty),
                  (mainName, Set.singleton utilsName)
                ]
            levels = Parallel.computeCheckLevels deps
        length levels @?= 2
        assertBool "Utils should be in first level"
          (utilsName `elem` Parallel._levelModules (levels !! 0))
        assertBool "Main should be in second level"
          (mainName `elem` Parallel._levelModules (levels !! 1)),
      testCase "three-level chain" $ do
        let deps =
              Map.fromList
                [ (aName, Set.empty),
                  (bName, Set.singleton aName),
                  (cName, Set.singleton bName)
                ]
            levels = Parallel.computeCheckLevels deps
        length levels @?= 3,
      testCase "diamond dependency produces two levels" $ do
        let deps =
              Map.fromList
                [ (aName, Set.empty),
                  (bName, Set.singleton aName),
                  (cName, Set.singleton aName),
                  (dName, Set.fromList [bName, cName])
                ]
            levels = Parallel.computeCheckLevels deps
        length levels @?= 3
        assertBool "A should be in first level"
          (aName `elem` Parallel._levelModules (levels !! 0))
        assertBool "D should be in last level"
          (dName `elem` Parallel._levelModules (levels !! 2)),
      testCase "modules with external deps only are level 0" $ do
        let externalDep = Name.fromChars "External"
            deps =
              Map.fromList
                [ (mainName, Set.singleton externalDep)
                ]
            levels = Parallel.computeCheckLevels deps
        -- External dep not in the map, so Main's dep is considered satisfied
        length levels @?= 1,
      testCase "all modules in levels cover input" $ do
        let deps =
              Map.fromList
                [ (aName, Set.empty),
                  (bName, Set.singleton aName),
                  (cName, Set.empty),
                  (dName, Set.fromList [bName, cName])
                ]
            levels = Parallel.computeCheckLevels deps
            allInLevels = concatMap Parallel._levelModules levels
        length allInLevels @?= 4
        assertBool "A should be in levels" (aName `elem` allInLevels)
        assertBool "B should be in levels" (bName `elem` allInLevels)
        assertBool "C should be in levels" (cName `elem` allInLevels)
        assertBool "D should be in levels" (dName `elem` allInLevels)
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- typeCheckLevel
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testTypeCheckLevel :: TestTree
testTypeCheckLevel =
  testGroup
    "typeCheckLevel"
    [ testCase "processes all modules in level" $ do
        let level = Parallel.CheckLevel [mainName, utilsName]
            checkOne modName = pure (Parallel.TypeCheckResult modName (Right ()))
        results <- Parallel.typeCheckLevel checkOne level
        length results @?= 2,
      testCase "empty level produces empty results" $ do
        let level = Parallel.CheckLevel []
            checkOne :: ModuleName.Raw -> IO (Parallel.TypeCheckResult String ())
            checkOne modName = pure (Parallel.TypeCheckResult modName (Right ()))
        results <- Parallel.typeCheckLevel checkOne level
        results @?= [],
      testCase "errors are preserved in results" $ do
        let level = Parallel.CheckLevel [mainName, utilsName]
            checkOne modName
              | modName == mainName =
                  pure (Parallel.TypeCheckResult modName (Left ("type error" :: String)))
              | otherwise =
                  pure (Parallel.TypeCheckResult modName (Right ()))
        results <- Parallel.typeCheckLevel checkOne level
        let errors = filter (isLeft . Parallel._tcrResult) results
        length errors @?= 1,
      testCase "result module names match input" $ do
        let level = Parallel.CheckLevel [aName, bName, cName]
            checkOne modName = pure (Parallel.TypeCheckResult modName (Right ()))
        results <- Parallel.typeCheckLevel checkOne level
        let resultNames = map Parallel._tcrModule results
        Set.fromList resultNames @?= Set.fromList [aName, bName, cName]
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Helpers
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

mainName :: ModuleName.Raw
mainName = Name.fromChars "Main"

utilsName :: ModuleName.Raw
utilsName = Name.fromChars "Utils"

aName :: ModuleName.Raw
aName = Name.fromChars "A"

bName :: ModuleName.Raw
bName = Name.fromChars "B"

cName :: ModuleName.Raw
cName = Name.fromChars "C"

dName :: ModuleName.Raw
dName = Name.fromChars "D"

testInterface :: Interface.Interface
testInterface =
  Interface.Interface
    { Interface._home = Pkg.core,
      Interface._values = Map.empty,
      Interface._unions = Map.empty,
      Interface._aliases = Map.empty,
      Interface._binops = Map.empty,
      Interface._ifaceGuards = Map.empty,
      Interface._ifaceAbilities = Map.empty,
      Interface._ifaceImpls = []
    }

-- | Assert that a Maybe value is Just.
assertJust :: String -> Maybe a -> Assertion
assertJust _ (Just _) = pure ()
assertJust msg Nothing = assertFailure msg

-- | Check if an Either is Left.
isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

-- | Extract module lists from check levels.
extractModules :: [Parallel.CheckLevel] -> [[ModuleName.Raw]]
extractModules = map Parallel._levelModules
