{-# LANGUAGE OverloadedStrings #-}

-- | Test suite for the Type.Ability module.
--
-- Covers 'emptyAbilityEnv', 'lookupMethod', 'resolveAbility', and
-- 'checkAbilityConstraints' in isolation, without involving the constraint
-- solver. Because 'AbilityConstraint' carries a 'Variable' that is only
-- read for error reporting (not dereferenced during 'checkAbilityConstraints'),
-- we use a freshly minted flex variable wherever a variable is required.
--
-- @since 0.20.0
module Unit.Type.AbilityConstraintTest (tests) where

import qualified AST.Canonical as Can
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, isNothing)
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.HUnit
import Type.Ability
  ( AbilityConstraint (..),
    AbilityEnv (..),
    AbilityError (..),
    AbilityInfo (..),
    ImplInfo (..),
    checkAbilityConstraints,
    emptyAbilityEnv,
    lookupMethod,
    resolveAbility,
  )
import qualified Type.Type as Type

-- HELPERS

-- | A standard region used across all test constraints.
testRegion :: Ann.Region
testRegion =
  Ann.Region (Ann.Position 1 1) (Ann.Position 1 1)

-- | Build an 'AbilityConstraint' for a named ability, using a fresh flex var
-- as the type variable. The variable content does not affect any of the
-- pure operations tested here.
mkAbilityConstraint :: Name.Name -> IO AbilityConstraint
mkAbilityConstraint abilityName = do
  typeVar <- Type.mkFlexVar
  pure (AbilityConstraint abilityName typeVar testRegion)

-- | Build a minimal 'AbilityInfo' with the given method names mapped to
-- @Type.int@ as a placeholder type.
mkAbilityInfo :: [Name.Name] -> AbilityInfo
mkAbilityInfo methodNames =
  AbilityInfo
    { _aiMethods = Map.fromList (map (\n -> (n, Type.int)) methodNames)
    , _aiSuperAbilities = []
    }

-- | Build a complete 'ImplInfo' providing implementations for all listed
-- method names. Each method maps to a trivial 'Can.Def'; the test never
-- executes these definitions — only the presence of the name matters.
mkCompleteImpl :: [Name.Name] -> ImplInfo
mkCompleteImpl methodNames =
  ImplInfo { _iiMethods = Map.fromList (map (\n -> (n, dummyDef)) methodNames) }

-- | An 'ImplInfo' that is missing all method implementations.
emptyImpl :: ImplInfo
emptyImpl =
  ImplInfo { _iiMethods = Map.empty }

-- | A placeholder 'Can.Def' for constructing 'ImplInfo' values.
-- The test never executes this definition — only its name matters.
dummyDef :: Can.Def
dummyDef =
  Can.Def
    (Ann.At testRegion (Name.fromChars "_"))
    []
    (Ann.At testRegion Can.Unit)

-- | Assert that 'checkAbilityConstraints' returned 'Right ()'.
assertConstraintsRight :: Either [AbilityError] () -> IO ()
assertConstraintsRight (Right ()) = pure ()
assertConstraintsRight (Left _) = assertFailure "expected Right () but got Left"

-- | Assert that 'checkAbilityConstraints' returned 'Left' and that the
-- error list satisfies the given predicate.
assertConstraintsLeft :: ([AbilityError] -> Bool) -> Either [AbilityError] () -> IO ()
assertConstraintsLeft _ (Right ()) = assertFailure "expected Left but got Right ()"
assertConstraintsLeft p (Left errs) =
  assertBool "error list did not satisfy predicate" (p errs)

-- | Check whether an 'AbilityError' is an 'IncompleteImpl' for the given
-- ability and type pair.
isIncompleteImplFor :: Name.Name -> Name.Name -> AbilityError -> Bool
isIncompleteImplFor ability typeName (IncompleteImpl a t _) = a == ability && t == typeName
isIncompleteImplFor _ _ _ = False

-- TESTS

tests :: TestTree
tests =
  testGroup
    "Type.Ability Tests"
    [ emptyEnvTests,
      lookupMethodTests,
      resolveAbilityTests,
      checkConstraintsTests
    ]

-- EMPTY ENV TESTS

-- | An empty 'AbilityEnv' contains no abilities and no implementations.
-- All queries on it must return the appropriate empty/Nothing result.
emptyEnvTests :: TestTree
emptyEnvTests =
  testGroup
    "emptyAbilityEnv"
    [ testCase "lookupMethod returns Nothing on empty env" $
        assertBool "expected Nothing" (isNothing (lookupMethod emptyAbilityEnv "eq")),
      testCase "resolveAbility returns Nothing on empty env" $
        assertBool "expected Nothing" (isNothing (resolveAbility emptyAbilityEnv "Eq" "Int")),
      testCase "checkAbilityConstraints succeeds with empty env and no constraints" $
        assertConstraintsRight (checkAbilityConstraints emptyAbilityEnv []),
      testCase "checkAbilityConstraints succeeds with empty env and one constraint" $ do
        constraint <- mkAbilityConstraint "Eq"
        assertConstraintsRight (checkAbilityConstraints emptyAbilityEnv [constraint])
    ]

-- LOOKUP METHOD TESTS

-- | 'lookupMethod' should find a method defined under a declared ability
-- and return @Just (abilityName, methodType)@. It should return 'Nothing'
-- for names that are not registered as ability methods.
lookupMethodTests :: TestTree
lookupMethodTests =
  testGroup
    "lookupMethod"
    [ testCase "lookupMethod finds registered method" $
        assertBool "expected Just" (isJust (lookupMethod envWithEq "eq")),
      testCase "lookupMethod returns Nothing for unknown method" $
        assertBool "expected Nothing" (isNothing (lookupMethod envWithEq "compare")),
      testCase "lookupMethod returns Nothing when no abilities declared" $
        assertBool "expected Nothing" (isNothing (lookupMethod emptyAbilityEnv "eq")),
      testCase "lookupMethod finds method in second ability" $
        assertBool "expected Just" (isJust (lookupMethod envWithEqAndOrd "compare")),
      testCase "lookupMethod returns ability name for eq in envWithEqAndOrd" $
        fmap fst (lookupMethod envWithEqAndOrd "eq") @?= Just "Eq",
      testCase "lookupMethod returns ability name for compare in envWithEqAndOrd" $
        fmap fst (lookupMethod envWithEqAndOrd "compare") @?= Just "Ord"
    ]

-- | Env with a single @Eq@ ability declaring one method @"eq"@.
envWithEq :: AbilityEnv
envWithEq =
  AbilityEnv
    { _aeAbilities = Map.singleton "Eq" (mkAbilityInfo ["eq"])
    , _aeImpls = Map.empty
    }

-- | Env with @Eq@ (method @"eq"@) and @Ord@ (method @"compare"@).
envWithEqAndOrd :: AbilityEnv
envWithEqAndOrd =
  AbilityEnv
    { _aeAbilities =
        Map.fromList
          [ ("Eq", mkAbilityInfo ["eq"])
          , ("Ord", mkAbilityInfo ["compare"])
          ]
    , _aeImpls = Map.empty
    }

-- RESOLVE ABILITY TESTS

-- | 'resolveAbility' looks up an @(abilityName, typeName)@ pair in
-- '_aeImpls'. It returns 'Just' when the pair is present, 'Nothing'
-- otherwise.
resolveAbilityTests :: TestTree
resolveAbilityTests =
  testGroup
    "resolveAbility"
    [ testCase "resolveAbility finds existing implementation" $
        assertBool "expected Just" (isJust (resolveAbility envWithImpl "Eq" "Int")),
      testCase "resolveAbility returns Nothing for absent type" $
        assertBool "expected Nothing" (isNothing (resolveAbility envWithImpl "Eq" "Bool")),
      testCase "resolveAbility returns Nothing for absent ability" $
        assertBool "expected Nothing" (isNothing (resolveAbility envWithImpl "Ord" "Int"))
    ]

-- | Env where @Eq@ is declared and has a complete implementation for @Int@.
envWithImpl :: AbilityEnv
envWithImpl =
  AbilityEnv
    { _aeAbilities = Map.singleton "Eq" (mkAbilityInfo ["eq"])
    , _aeImpls = Map.singleton ("Eq", "Int") (mkCompleteImpl ["eq"])
    }

-- CHECK CONSTRAINTS TESTS

-- | 'checkAbilityConstraints' returns @Right ()@ when all registered
-- implementations are complete, and @Left errors@ when any are incomplete.
-- Constraints for abilities not present in '_aeAbilities' are silently
-- skipped.
checkConstraintsTests :: TestTree
checkConstraintsTests =
  testGroup
    "checkAbilityConstraints"
    [ testCheckNoConstraints,
      testCheckConstraintForUnknownAbility,
      testCheckCompleteImplSucceeds,
      testCheckIncompleteImplFails,
      testCheckMultipleConstraintsMixed
    ]

-- | No constraints always produces @Right ()@.
testCheckNoConstraints :: TestTree
testCheckNoConstraints =
  testCase "no constraints always produces Right" $
    assertConstraintsRight (checkAbilityConstraints envWithEq [])

-- | A constraint for an ability name not in '_aeAbilities' is silently
-- skipped. This is the documented behaviour for externally-satisfied abilities.
testCheckConstraintForUnknownAbility :: TestTree
testCheckConstraintForUnknownAbility =
  testCase "constraint for undeclared ability is silently skipped" $ do
    constraint <- mkAbilityConstraint "UnknownAbility"
    assertConstraintsRight (checkAbilityConstraints envWithEq [constraint])

-- | An ability with a complete implementation (all declared methods present)
-- produces no errors.
testCheckCompleteImplSucceeds :: TestTree
testCheckCompleteImplSucceeds =
  testCase "complete implementation produces Right" $ do
    constraint <- mkAbilityConstraint "Eq"
    assertConstraintsRight (checkAbilityConstraints envWithImpl [constraint])

-- | An ability whose registered implementation is missing required methods
-- produces an 'IncompleteImpl' error carrying the missing method names.
testCheckIncompleteImplFails :: TestTree
testCheckIncompleteImplFails =
  testCase "incomplete implementation produces IncompleteImpl error" $ do
    constraint <- mkAbilityConstraint "Eq"
    let env = AbilityEnv
          { _aeAbilities = Map.singleton "Eq" (mkAbilityInfo ["eq", "neq"])
          , _aeImpls = Map.singleton ("Eq", "Int") emptyImpl
          }
    assertConstraintsLeft
      (any (isIncompleteImplFor "Eq" "Int"))
      (checkAbilityConstraints env [constraint])

-- | Multiple constraints where one is for a known ability with a complete
-- implementation (no error) and one is for an unknown ability (silently
-- skipped). The combined result must be @Right ()@.
testCheckMultipleConstraintsMixed :: TestTree
testCheckMultipleConstraintsMixed =
  testCase "mixed known-complete and unknown constraints produces Right" $ do
    knownConstraint <- mkAbilityConstraint "Eq"
    unknownConstraint <- mkAbilityConstraint "SomeOtherAbility"
    assertConstraintsRight
      (checkAbilityConstraints envWithImpl [knownConstraint, unknownConstraint])
