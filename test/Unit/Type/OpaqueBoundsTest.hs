{-# LANGUAGE OverloadedStrings #-}

-- | Tests for opaque type alias supertype bounds.
--
-- Verifies that opaque types with declared bounds (comparable, appendable,
-- number, compappend) correctly satisfy super type constraints during
-- unification. Tests cover:
--
-- * Direct unification of bounded opaque types with FlexSuper variables
-- * Solver integration via runWithBounds
-- * Interface bounds extraction
-- * Negative cases (missing/wrong bounds)
--
-- @since 0.19.2
module Unit.Type.OpaqueBoundsTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Type as Error
import Test.Tasty
import Test.Tasty.HUnit
import qualified Type.Solve as Solve
import Type.Type
  ( Constraint (..),
    Content (..),
    Descriptor (Descriptor),
    FlatType (..),
    SuperType (..),
    Type (..),
    Variable,
    noMark,
    noRank,
  )
import qualified Type.Type as Type
import Type.Unify (Answer (..), BoundsMap)
import qualified Type.Unify as Unify
import qualified Type.UnionFind as UF

-- TEST HELPERS

-- | Test package for opaque type definitions.
testPkg :: Pkg.Name
testPkg = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "app")

-- | Canonical module name for test types.
testModuleName :: ModuleName.Canonical
testModuleName = ModuleName.Canonical testPkg (Name.fromChars "MyTypes")

-- | A second module for cross-module tests.
otherModuleName :: ModuleName.Canonical
otherModuleName = ModuleName.Canonical testPkg (Name.fromChars "OtherTypes")

-- | Create a variable with a given FlatType structure.
mkStructureVar :: FlatType -> IO Variable
mkStructureVar ft =
  UF.fresh (Descriptor (Structure ft) noRank noMark Nothing)

-- | Create a FlexSuper variable with the given super type.
mkFlexSuperVar :: SuperType -> IO Variable
mkFlexSuperVar super =
  UF.fresh (Descriptor (FlexSuper super Nothing) noRank noMark Nothing)

-- | Create a variable representing an opaque type (nominal, no args).
mkOpaqueVar :: ModuleName.Canonical -> Name.Name -> IO Variable
mkOpaqueVar home typeName =
  mkStructureVar (App1 home typeName [])

-- | Check whether a unification Answer is Ok.
isOk :: Answer -> Bool
isOk (Ok _) = True
isOk (Err _ _ _) = False

-- | Check whether a unification Answer is Err.
isErr :: Answer -> Bool
isErr = not . isOk

-- | Assert solve success.
assertSolveSuccess :: Either a b -> IO ()
assertSolveSuccess result =
  assertBool "expected solver to succeed (Right)" (isRight result)

-- | Assert solve failure.
assertSolveFailure :: Either a b -> IO ()
assertSolveFailure result =
  assertBool "expected solver to fail (Left)" (isLeft result)

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False

isLeft :: Either a b -> Bool
isLeft = not . isRight

-- | Standard test region.
testRegion :: Ann.Region
testRegion =
  Ann.Region (Ann.Position 1 1) (Ann.Position 1 1)

-- | Build a CEqual constraint.
mkCEqual :: Type -> Type -> Constraint
mkCEqual actual expected =
  CEqual testRegion Error.Number actual (Error.NoExpectation expected)

-- | Create a bounds map with a single entry.
singleBound :: ModuleName.Canonical -> Name.Name -> SuperType -> BoundsMap
singleBound home typeName super =
  Map.singleton (home, typeName) super

-- | Make a Can.Alias with a supertype bound.
mkBoundedAlias :: Can.SupertypeBound -> Can.Alias
mkBoundedAlias bound =
  Can.Alias [] [] Can.TUnit (Just bound)

-- | Make a Can.Alias without a bound.
mkUnboundedAlias :: Can.Alias
mkUnboundedAlias =
  Can.Alias [] [] Can.TUnit Nothing

-- TESTS

tests :: TestTree
tests =
  testGroup
    "Opaque Bounds Tests"
    [ unifyBoundedOpaqueTests,
      solveWithBoundsTests,
      interfaceBoundsExtractionTests,
      boundSatisfactionTests
    ]

-- UNIFICATION WITH BOUNDED OPAQUE TYPES

unifyBoundedOpaqueTests :: TestTree
unifyBoundedOpaqueTests =
  testGroup
    "unification with bounded opaque types"
    [ testCase "comparable-bounded opaque type unifies with FlexSuper Comparable" $ do
        let userIdName = Name.fromChars "UserId"
            bounds = singleBound testModuleName userIdName Comparable
        opaqueVar <- mkOpaqueVar testModuleName userIdName
        compVar <- mkFlexSuperVar Comparable
        answer <- Unify.unify bounds compVar opaqueVar
        assertBool "expected Ok for comparable ~ UserId(comparable)" (isOk answer),
      testCase "number-bounded opaque type unifies with FlexSuper Number" $ do
        let scoreName = Name.fromChars "Score"
            bounds = singleBound testModuleName scoreName Number
        opaqueVar <- mkOpaqueVar testModuleName scoreName
        numVar <- mkFlexSuperVar Number
        answer <- Unify.unify bounds numVar opaqueVar
        assertBool "expected Ok for number ~ Score(number)" (isOk answer),
      testCase "appendable-bounded opaque type unifies with FlexSuper Appendable" $ do
        let logName = Name.fromChars "LogEntry"
            bounds = singleBound testModuleName logName Appendable
        opaqueVar <- mkOpaqueVar testModuleName logName
        appVar <- mkFlexSuperVar Appendable
        answer <- Unify.unify bounds appVar opaqueVar
        assertBool "expected Ok for appendable ~ LogEntry(appendable)" (isOk answer),
      testCase "compappend-bounded opaque type unifies with FlexSuper Comparable" $ do
        let tagName = Name.fromChars "Tag"
            bounds = singleBound testModuleName tagName CompAppend
        opaqueVar <- mkOpaqueVar testModuleName tagName
        compVar <- mkFlexSuperVar Comparable
        answer <- Unify.unify bounds compVar opaqueVar
        assertBool "expected Ok for comparable ~ Tag(compappend)" (isOk answer),
      testCase "compappend-bounded opaque type unifies with FlexSuper Appendable" $ do
        let tagName = Name.fromChars "Tag"
            bounds = singleBound testModuleName tagName CompAppend
        opaqueVar <- mkOpaqueVar testModuleName tagName
        appVar <- mkFlexSuperVar Appendable
        answer <- Unify.unify bounds appVar opaqueVar
        assertBool "expected Ok for appendable ~ Tag(compappend)" (isOk answer),
      testCase "number-bounded opaque type satisfies comparable" $ do
        let scoreName = Name.fromChars "Score"
            bounds = singleBound testModuleName scoreName Number
        opaqueVar <- mkOpaqueVar testModuleName scoreName
        compVar <- mkFlexSuperVar Comparable
        answer <- Unify.unify bounds compVar opaqueVar
        assertBool "expected Ok for comparable ~ Score(number)" (isOk answer),
      testCase "unbounded opaque type fails with FlexSuper Comparable" $ do
        let widgetName = Name.fromChars "Widget"
        opaqueVar <- mkOpaqueVar testModuleName widgetName
        compVar <- mkFlexSuperVar Comparable
        answer <- Unify.unify Map.empty compVar opaqueVar
        assertBool "expected Err for comparable ~ Widget(no bound)" (isErr answer),
      testCase "comparable-bounded opaque type fails with FlexSuper Appendable" $ do
        let userIdName = Name.fromChars "UserId"
            bounds = singleBound testModuleName userIdName Comparable
        opaqueVar <- mkOpaqueVar testModuleName userIdName
        appVar <- mkFlexSuperVar Appendable
        answer <- Unify.unify bounds appVar opaqueVar
        assertBool "expected Err for appendable ~ UserId(comparable)" (isErr answer),
      testCase "comparable-bounded opaque type fails with FlexSuper Number" $ do
        let userIdName = Name.fromChars "UserId"
            bounds = singleBound testModuleName userIdName Comparable
        opaqueVar <- mkOpaqueVar testModuleName userIdName
        numVar <- mkFlexSuperVar Number
        answer <- Unify.unify bounds numVar opaqueVar
        assertBool "expected Err for number ~ UserId(comparable)" (isErr answer),
      testCase "cross-module bounded opaque types are independent" $ do
        let userIdName = Name.fromChars "UserId"
            bounds = singleBound testModuleName userIdName Comparable
        opaqueVar <- mkOpaqueVar otherModuleName userIdName
        compVar <- mkFlexSuperVar Comparable
        answer <- Unify.unify bounds compVar opaqueVar
        assertBool "expected Err for comparable ~ OtherTypes.UserId (not registered)" (isErr answer),
      testCase "multiple bounds work simultaneously" $ do
        let bounds =
              Map.fromList
                [ ((testModuleName, Name.fromChars "UserId"), Comparable),
                  ((testModuleName, Name.fromChars "Score"), Number),
                  ((otherModuleName, Name.fromChars "LogMsg"), Appendable)
                ]
        uid <- mkOpaqueVar testModuleName (Name.fromChars "UserId")
        comp <- mkFlexSuperVar Comparable
        a1 <- Unify.unify bounds comp uid
        assertBool "UserId ~ comparable" (isOk a1)

        score <- mkOpaqueVar testModuleName (Name.fromChars "Score")
        num <- mkFlexSuperVar Number
        a2 <- Unify.unify bounds num score
        assertBool "Score ~ number" (isOk a2)

        logMsg <- mkOpaqueVar otherModuleName (Name.fromChars "LogMsg")
        app <- mkFlexSuperVar Appendable
        a3 <- Unify.unify bounds app logMsg
        assertBool "LogMsg ~ appendable" (isOk a3)
    ]

-- SOLVER INTEGRATION

solveWithBoundsTests :: TestTree
solveWithBoundsTests =
  testGroup
    "solver with bounds (runWithBounds)"
    [ testCase "CTrue with empty bounds succeeds" $ do
        result <- Solve.runWithBounds Map.empty CTrue
        assertSolveSuccess result,
      testCase "CEqual int int with bounds succeeds" $ do
        result <- Solve.runWithBounds Map.empty (mkCEqual Type.int Type.int)
        assertSolveSuccess result,
      testCase "CEqual int string with bounds fails" $ do
        result <- Solve.runWithBounds Map.empty (mkCEqual Type.int Type.string)
        assertSolveFailure result,
      testCase "run delegates to runWithBounds empty" $ do
        resultRun <- Solve.run CTrue
        resultBounds <- Solve.runWithBounds Map.empty CTrue
        assertSolveSuccess resultRun
        assertSolveSuccess resultBounds
    ]

-- INTERFACE BOUNDS EXTRACTION

interfaceBoundsExtractionTests :: TestTree
interfaceBoundsExtractionTests =
  testGroup
    "interface bounds extraction"
    [ testCase "extractBoundsFromAliases finds comparable-bounded alias" $ do
        let aliases = Map.singleton (Name.fromChars "UserId") (mkBoundedAlias Can.ComparableBound)
            bounds = Solve.extractBoundsFromAliases testModuleName aliases
        Map.size bounds @?= 1
        Map.member (testModuleName, Name.fromChars "UserId") bounds @?= True,
      testCase "extractBoundsFromAliases skips unbounded alias" $ do
        let aliases = Map.singleton (Name.fromChars "Widget") mkUnboundedAlias
            bounds = Solve.extractBoundsFromAliases testModuleName aliases
        Map.null bounds @?= True,
      testCase "extractBoundsFromAliases handles mixed aliases" $ do
        let aliases =
              Map.fromList
                [ (Name.fromChars "UserId", mkBoundedAlias Can.ComparableBound),
                  (Name.fromChars "Widget", mkUnboundedAlias),
                  (Name.fromChars "Score", mkBoundedAlias Can.NumberBound)
                ]
            bounds = Solve.extractBoundsFromAliases testModuleName aliases
        Map.size bounds @?= 2
        Map.member (testModuleName, Name.fromChars "UserId") bounds @?= True
        Map.member (testModuleName, Name.fromChars "Score") bounds @?= True
        Map.member (testModuleName, Name.fromChars "Widget") bounds @?= False,
      testCase "extractAllInterfaceBounds collects from multiple interfaces" $ do
        let userIdAlias = Interface.OpaqueAlias (mkBoundedAlias Can.ComparableBound)
            scoreAlias = Interface.OpaqueAlias (mkBoundedAlias Can.NumberBound)
            widgetAlias = Interface.PublicAlias mkUnboundedAlias
            iface1 = Interface.Interface testPkg Map.empty Map.empty (Map.singleton (Name.fromChars "UserId") userIdAlias) Map.empty Map.empty
            iface2 = Interface.Interface testPkg Map.empty Map.empty (Map.fromList [(Name.fromChars "Score", scoreAlias), (Name.fromChars "Widget", widgetAlias)]) Map.empty Map.empty
            ifaceMap = Map.fromList [(Name.fromChars "MyTypes", iface1), (Name.fromChars "OtherTypes", iface2)]
            bounds = Solve.extractAllInterfaceBounds ifaceMap
        Map.size bounds @?= 2
        Map.member (testModuleName, Name.fromChars "UserId") bounds @?= True
        Map.member (ModuleName.Canonical testPkg (Name.fromChars "OtherTypes"), Name.fromChars "Score") bounds @?= True,
      testCase "extractAllInterfaceBounds with empty interfaces returns empty" $ do
        let bounds = Solve.extractAllInterfaceBounds Map.empty
        Map.null bounds @?= True
    ]

-- BOUND SATISFACTION LOGIC

boundSatisfactionTests :: TestTree
boundSatisfactionTests =
  testGroup
    "bound satisfaction semantics"
    [ testCase "number satisfies comparable" $ do
        let bounds = singleBound testModuleName (Name.fromChars "X") Number
        opaqueVar <- mkOpaqueVar testModuleName (Name.fromChars "X")
        compVar <- mkFlexSuperVar Comparable
        answer <- Unify.unify bounds compVar opaqueVar
        assertBool "number should satisfy comparable" (isOk answer),
      testCase "compappend satisfies comparable" $ do
        let bounds = singleBound testModuleName (Name.fromChars "X") CompAppend
        opaqueVar <- mkOpaqueVar testModuleName (Name.fromChars "X")
        compVar <- mkFlexSuperVar Comparable
        answer <- Unify.unify bounds compVar opaqueVar
        assertBool "compappend should satisfy comparable" (isOk answer),
      testCase "compappend satisfies appendable" $ do
        let bounds = singleBound testModuleName (Name.fromChars "X") CompAppend
        opaqueVar <- mkOpaqueVar testModuleName (Name.fromChars "X")
        appVar <- mkFlexSuperVar Appendable
        answer <- Unify.unify bounds appVar opaqueVar
        assertBool "compappend should satisfy appendable" (isOk answer),
      testCase "comparable does not satisfy number" $ do
        let bounds = singleBound testModuleName (Name.fromChars "X") Comparable
        opaqueVar <- mkOpaqueVar testModuleName (Name.fromChars "X")
        numVar <- mkFlexSuperVar Number
        answer <- Unify.unify bounds numVar opaqueVar
        assertBool "comparable should not satisfy number" (isErr answer),
      testCase "appendable does not satisfy comparable" $ do
        let bounds = singleBound testModuleName (Name.fromChars "X") Appendable
        opaqueVar <- mkOpaqueVar testModuleName (Name.fromChars "X")
        compVar <- mkFlexSuperVar Comparable
        answer <- Unify.unify bounds compVar opaqueVar
        assertBool "appendable should not satisfy comparable" (isErr answer),
      testCase "appendable does not satisfy number" $ do
        let bounds = singleBound testModuleName (Name.fromChars "X") Appendable
        opaqueVar <- mkOpaqueVar testModuleName (Name.fromChars "X")
        numVar <- mkFlexSuperVar Number
        answer <- Unify.unify bounds numVar opaqueVar
        assertBool "appendable should not satisfy number" (isErr answer),
      testCase "number does not satisfy appendable" $ do
        let bounds = singleBound testModuleName (Name.fromChars "X") Number
        opaqueVar <- mkOpaqueVar testModuleName (Name.fromChars "X")
        appVar <- mkFlexSuperVar Appendable
        answer <- Unify.unify bounds appVar opaqueVar
        assertBool "number should not satisfy appendable" (isErr answer)
    ]
