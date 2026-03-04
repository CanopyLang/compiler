{-# LANGUAGE OverloadedStrings #-}

-- | Comprehensive tests for type guard narrowing in constraint generation.
--
-- Tests the guard detection and type narrowing logic that occurs when
-- the constraint generator processes @if@ expressions whose conditions
-- call guard functions. When a condition calls a guard, the then-branch
-- sees the guarded argument with a narrowed type.
--
-- Since the internal @Control.constrainIf@ function is not exported, these
-- tests verify narrowing through two approaches:
--
-- 1. Solver-level tests: Build CLet constraints that match the narrowing
--    pattern (CLet [] flexVars header CTrue innerCon Nothing) and verify
--    the solver handles them correctly.
--
-- 2. Module-level tests: Build full Can.Module ASTs with guard annotations
--    and if-expressions, run Module.constrain, and verify solver results.
--
-- Test categories:
--
-- * Narrowing CLet structure: solver accepts narrowing-shaped constraints
-- * Variable shadowing: CLet header shadows variables correctly
-- * Free variable handling: correct flex var creation for narrow types
-- * Module-level integration: full Can.Module with guards through solver
-- * Edge cases: empty headers, nested CLets, type mismatches
--
-- @since 0.20.0
module Unit.Type.GuardNarrowingTest (tests) where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Type as Error
import Test.Tasty
import Test.Tasty.HUnit
import qualified Type.Constrain.Module as Module
import qualified Type.Instantiate as Instantiate
import qualified Type.Solve as Solve
import Type.Type (Constraint (..), Type (..))
import qualified Type.Type as Type

-- HELPERS

-- | Standard test region.
testRegion :: Ann.Region
testRegion =
  Ann.Region (Ann.Position 1 1) (Ann.Position 1 1)

-- | Test package for building canonical module names.
testPkg :: Pkg.Name
testPkg = Pkg.Name (Utf8.fromChars "test") (Utf8.fromChars "app")

-- | Canonical module name for test types.
testModuleName :: ModuleName.Canonical
testModuleName = ModuleName.Canonical testPkg (Name.fromChars "Main")

-- | Build a located expression at the test region.
loc :: Can.Expr_ -> Can.Expr
loc = Ann.At testRegion

-- | Build a located name at the test region.
locName :: Name.Name -> Ann.Located Name.Name
locName = Ann.At testRegion

-- | Build a local variable expression.
localVar :: Name.Name -> Can.Expr
localVar name = loc (Can.VarLocal name)

-- | Build a top-level variable expression.
topLevelVar :: ModuleName.Canonical -> Name.Name -> Can.Expr
topLevelVar home name = loc (Can.VarTopLevel home name)

-- | Build a call expression: @func arg1 arg2 ...@
callExpr :: Can.Expr -> [Can.Expr] -> Can.Expr
callExpr func args = loc (Can.Call func args)

-- | Build an Int literal expression.
intExpr :: Int -> Can.Expr
intExpr n = loc (Can.Int n)

-- | Build a string literal expression.
strExpr :: Can.Expr
strExpr = loc (Can.Str (Utf8.fromChars "hello"))

-- | Build an if expression with the given branches and final.
ifExpr :: [(Can.Expr, Can.Expr)] -> Can.Expr -> Can.Expr
ifExpr branches final = loc (Can.If branches final)

-- | Build a guard info entry.
mkGuardInfo :: Int -> Can.Type -> Can.GuardInfo
mkGuardInfo = Can.GuardInfo

-- | Build a guard map with a single entry.
singleGuard :: Name.Name -> Int -> Can.Type -> Map Name.Name Can.GuardInfo
singleGuard name argIdx narrowType =
  Map.singleton name (mkGuardInfo argIdx narrowType)

-- | Build a CEqual constraint.
mkCEqual :: Type -> Type -> Constraint
mkCEqual actual expected =
  CEqual testRegion Error.Number actual (Error.NoExpectation expected)

-- | Build a minimal Can.Module with the given declarations and guards.
mkModule :: Can.Decls -> Map Name.Name Can.GuardInfo -> Can.Module
mkModule decls guards =
  Can.Module
    testModuleName
    (Can.ExportEverything testRegion)
    (Src.NoDocs testRegion)
    decls
    Map.empty
    Map.empty
    Map.empty
    Can.NoEffects
    mempty
    guards

-- | Build a simple untyped definition: @name = body@
mkDef :: Name.Name -> Can.Expr -> Can.Def
mkDef name body =
  Can.Def (locName name) [] body

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

-- TESTS

tests :: TestTree
tests =
  testGroup
    "Guard Narrowing Tests"
    [ narrowingCLetTests,
      variableShadowingTests,
      freeVarInstantiationTests,
      moduleLevelNarrowingTests,
      edgeCaseTests,
      multipleNarrowingTests,
      typeVarietyTests
    ]

-- NARROWING CLET STRUCTURE TESTS

-- | Tests that CLet constraints matching the narrowing pattern
-- (CLet [] flexVars header CTrue innerCon Nothing) are handled
-- correctly by the solver. This is the constraint shape that
-- wrapWithNarrowing produces.
narrowingCLetTests :: TestTree
narrowingCLetTests =
  testGroup
    "narrowing CLet structure"
    [ testCase "CLet with narrowing shape and matching types succeeds" $ do
        flexVar <- Type.mkFlexVar
        let header = Map.singleton (Name.fromChars "x") (Ann.At Ann.zero Type.int)
        let innerCon = CLocal testRegion (Name.fromChars "x") (Error.NoExpectation Type.int)
        let constraint = CLet [] [flexVar] header CTrue innerCon Nothing
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "CLet narrowing with flex var unified in body succeeds" $ do
        flexVar <- Type.mkFlexVar
        let header = Map.singleton (Name.fromChars "y") (Ann.At Ann.zero (VarN flexVar))
        let innerCon = mkCEqual (VarN flexVar) Type.string
        let constraint = CLet [] [flexVar] header CTrue innerCon Nothing
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "CLet narrowing with empty flex vars and concrete type" $ do
        let header = Map.singleton (Name.fromChars "z") (Ann.At Ann.zero Type.bool)
        let innerCon = CLocal testRegion (Name.fromChars "z") (Error.NoExpectation Type.bool)
        let constraint = CLet [] [] header CTrue innerCon Nothing
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "CLet narrowing wrapping CAnd of multiple constraints" $ do
        flexVar <- Type.mkFlexVar
        let header = Map.singleton (Name.fromChars "a") (Ann.At Ann.zero Type.int)
        let inner1 = CLocal testRegion (Name.fromChars "a") (Error.NoExpectation Type.int)
        let inner2 = mkCEqual Type.int Type.int
        let innerCon = CAnd [inner1, inner2]
        let constraint = CLet [] [flexVar] header CTrue innerCon Nothing
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "CLet narrowing with CTrue inner constraint succeeds" $ do
        flexVar <- Type.mkFlexVar
        let header = Map.singleton (Name.fromChars "w") (Ann.At Ann.zero Type.float)
        let constraint = CLet [] [flexVar] header CTrue CTrue Nothing
        result <- Solve.run constraint
        assertSolveSuccess result
    ]

-- VARIABLE SHADOWING TESTS

-- | Tests that the CLet header correctly shadows variables in scope,
-- which is how guard narrowing works — it shadows the guarded variable
-- with the narrowed type in the then-branch.
variableShadowingTests :: TestTree
variableShadowingTests =
  testGroup
    "variable shadowing in narrowing"
    [ testCase "CLet shadows outer variable with narrowed type" $ do
        outerFlex <- Type.mkFlexVar
        let outerHeader = Map.singleton (Name.fromChars "x") (Ann.At Ann.zero (VarN outerFlex))
        let narrowHeader = Map.singleton (Name.fromChars "x") (Ann.At Ann.zero Type.int)
        let innerBody = CLocal testRegion (Name.fromChars "x") (Error.NoExpectation Type.int)
        let narrowLet = CLet [] [] narrowHeader CTrue innerBody Nothing
        let outerLet = CLet [] [outerFlex] outerHeader CTrue narrowLet Nothing
        result <- Solve.run outerLet
        assertSolveSuccess result,
      testCase "nested CLets do not interfere with each other" $ do
        outerFlex <- Type.mkFlexVar
        innerFlex <- Type.mkFlexVar
        let outerHeader = Map.singleton (Name.fromChars "outer") (Ann.At Ann.zero (VarN outerFlex))
        let innerHeader = Map.singleton (Name.fromChars "inner") (Ann.At Ann.zero (VarN innerFlex))
        let innerLet = CLet [] [innerFlex] innerHeader CTrue CTrue Nothing
        let outerLet = CLet [] [outerFlex] outerHeader CTrue innerLet Nothing
        result <- Solve.run outerLet
        assertSolveSuccess result,
      testCase "multiple narrowings in sequence via CAnd" $ do
        flex1 <- Type.mkFlexVar
        flex2 <- Type.mkFlexVar
        let header1 = Map.singleton (Name.fromChars "a") (Ann.At Ann.zero Type.int)
        let header2 = Map.singleton (Name.fromChars "b") (Ann.At Ann.zero Type.string)
        let let1 = CLet [] [flex1] header1 CTrue CTrue Nothing
        let let2 = CLet [] [flex2] header2 CTrue CTrue Nothing
        result <- Solve.run (CAnd [let1, let2])
        assertSolveSuccess result,
      testCase "shadowing with function type in header" $ do
        let funType = FunN Type.int Type.string
        let header = Map.singleton (Name.fromChars "f") (Ann.At Ann.zero funType)
        let innerCon = CLocal testRegion (Name.fromChars "f") (Error.NoExpectation funType)
        let constraint = CLet [] [] header CTrue innerCon Nothing
        result <- Solve.run constraint
        assertSolveSuccess result
    ]

-- FREE VARIABLE INSTANTIATION TESTS

-- | Tests that verify the Instantiate.fromSrcType function correctly
-- converts canonical types to solver types, which is used to instantiate
-- narrow types in the narrowing CLet.
freeVarInstantiationTests :: TestTree
freeVarInstantiationTests =
  testGroup
    "free variable instantiation"
    [ testCase "fromSrcType with TUnit produces UnitN" $ do
        narrowType <- Instantiate.fromSrcType Map.empty Can.TUnit
        let constraint = mkCEqual narrowType UnitN
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "fromSrcType with TVar and flex var mapping" $ do
        flexVar <- Type.mkFlexVar
        let varMap = Map.singleton (Name.fromChars "a") (VarN flexVar)
        narrowType <- Instantiate.fromSrcType varMap (Can.TVar (Name.fromChars "a"))
        let constraint = mkCEqual narrowType (VarN flexVar)
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "fromSrcType with TType produces AppN" $ do
        narrowType <- Instantiate.fromSrcType Map.empty (Can.TType testModuleName (Name.fromChars "Int") [])
        let expectedType = AppN testModuleName (Name.fromChars "Int") []
        let constraint = mkCEqual narrowType expectedType
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "fromSrcType with TLambda produces FunN" $ do
        narrowType <- Instantiate.fromSrcType Map.empty (Can.TLambda Can.TUnit Can.TUnit)
        let constraint = mkCEqual narrowType (FunN UnitN UnitN)
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "fromSrcType with parameterized TType and flex var" $ do
        flexVar <- Type.mkFlexVar
        let varMap = Map.singleton (Name.fromChars "a") (VarN flexVar)
        narrowType <- Instantiate.fromSrcType varMap (Can.TType testModuleName (Name.fromChars "List") [Can.TVar (Name.fromChars "a")])
        let expectedType = AppN testModuleName (Name.fromChars "List") [VarN flexVar]
        let constraint = mkCEqual narrowType expectedType
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "fromSrcType with TTuple produces TupleN" $ do
        narrowType <- Instantiate.fromSrcType Map.empty (Can.TTuple Can.TUnit Can.TUnit Nothing)
        let constraint = mkCEqual narrowType (TupleN UnitN UnitN Nothing)
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "fromSrcType with multiple free vars creates independent flex vars" $ do
        flex1 <- Type.mkFlexVar
        flex2 <- Type.mkFlexVar
        let varMap = Map.fromList [(Name.fromChars "a", VarN flex1), (Name.fromChars "b", VarN flex2)]
        narrowType <- Instantiate.fromSrcType varMap (Can.TTuple (Can.TVar (Name.fromChars "a")) (Can.TVar (Name.fromChars "b")) Nothing)
        let expectedType = TupleN (VarN flex1) (VarN flex2) Nothing
        let constraint = mkCEqual narrowType expectedType
        result <- Solve.run constraint
        assertSolveSuccess result
    ]

-- MODULE-LEVEL NARROWING TESTS

-- | Tests that verify the full pipeline from Can.Module through
-- Module.constrain to Solve.run, exercising the guard map threading.
moduleLevelNarrowingTests :: TestTree
moduleLevelNarrowingTests =
  testGroup
    "module-level narrowing"
    [ testCase "module with guard and if-expression generates valid constraints" $ do
        let guardName = Name.fromChars "isInt"
        let argName = Name.fromChars "x"
        let narrowType = Can.TType testModuleName (Name.fromChars "Int") []
        let guardMap = singleGuard guardName 0 narrowType
        let condition = callExpr (localVar guardName) [localVar argName]
        -- Use literal then-branch since argName is not bound at module level.
        -- The guard narrowing CLet still wraps this branch, testing the path.
        let body = ifExpr [(condition, intExpr 1)] (intExpr 0)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "module with empty guard map and if-expression succeeds" $ do
        let condition = localVar (Name.fromChars "flag")
        let body = ifExpr [(condition, intExpr 1)] (intExpr 2)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls Map.empty
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "module with guard but non-guard condition succeeds" $ do
        let guardName = Name.fromChars "isOk"
        let narrowType = Can.TType testModuleName (Name.fromChars "Ok") []
        let guardMap = singleGuard guardName 0 narrowType
        let condition = localVar (Name.fromChars "flag")
        let body = ifExpr [(condition, intExpr 1)] (intExpr 2)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "module with multiple declarations and guards" $ do
        let guardName = Name.fromChars "isNum"
        let narrowType = Can.TType testModuleName (Name.fromChars "Int") []
        let guardMap = singleGuard guardName 0 narrowType
        let def1 = mkDef (Name.fromChars "a") (intExpr 1)
        let condition = callExpr (localVar guardName) [localVar (Name.fromChars "x")]
        let def2 = mkDef (Name.fromChars "b") (ifExpr [(condition, intExpr 2)] (intExpr 3))
        let decls = Can.Declare def1 (Can.Declare def2 Can.SaveTheEnvironment)
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "module with SaveTheEnvironment only and guards succeeds" $ do
        let guardName = Name.fromChars "isOk"
        let narrowType = Can.TUnit
        let guardMap = singleGuard guardName 0 narrowType
        let canModule = mkModule Can.SaveTheEnvironment guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result
    ]

-- EDGE CASE TESTS

-- | Tests for edge cases in the narrowing mechanism.
edgeCaseTests :: TestTree
edgeCaseTests =
  testGroup
    "edge cases"
    [ testCase "CLet with empty header and CTrue succeeds" $ do
        let constraint = CLet [] [] Map.empty CTrue CTrue Nothing
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "CLet narrowing body with mismatched types fails" $ do
        let header = Map.singleton (Name.fromChars "x") (Ann.At Ann.zero Type.int)
        let innerCon = CLocal testRegion (Name.fromChars "x") (Error.NoExpectation Type.string)
        let constraint = CLet [] [] header CTrue innerCon Nothing
        result <- Solve.run constraint
        assertSolveFailure result,
      testCase "deeply nested CLets from multiple narrowings" $ do
        flex1 <- Type.mkFlexVar
        flex2 <- Type.mkFlexVar
        flex3 <- Type.mkFlexVar
        let header1 = Map.singleton (Name.fromChars "a") (Ann.At Ann.zero (VarN flex1))
        let header2 = Map.singleton (Name.fromChars "b") (Ann.At Ann.zero (VarN flex2))
        let header3 = Map.singleton (Name.fromChars "c") (Ann.At Ann.zero (VarN flex3))
        let let3 = CLet [] [flex3] header3 CTrue CTrue Nothing
        let let2 = CLet [] [flex2] header2 CTrue let3 Nothing
        let let1 = CLet [] [flex1] header1 CTrue let2 Nothing
        result <- Solve.run let1
        assertSolveSuccess result,
      testCase "CLet with multiple flex vars in narrowing" $ do
        flex1 <- Type.mkFlexVar
        flex2 <- Type.mkFlexVar
        let tupleType = TupleN (VarN flex1) (VarN flex2) Nothing
        let header = Map.singleton (Name.fromChars "pair") (Ann.At Ann.zero tupleType)
        let innerCon = CLocal testRegion (Name.fromChars "pair") (Error.NoExpectation tupleType)
        let constraint = CLet [] [flex1, flex2] header CTrue innerCon Nothing
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "CLet narrowing with record type" $ do
        flexVar <- Type.mkFlexVar
        let recordType = RecordN (Map.singleton (Name.fromChars "field") (VarN flexVar)) EmptyRecordN
        let header = Map.singleton (Name.fromChars "rec") (Ann.At Ann.zero recordType)
        let constraint = CLet [] [flexVar] header CTrue CTrue Nothing
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "guard function with arg index 1 in module" $ do
        let guardName = Name.fromChars "isValid"
        let narrowType = Can.TType testModuleName (Name.fromChars "Valid") []
        let guardMap = singleGuard guardName 1 narrowType
        let condition = callExpr (localVar guardName) [strExpr, localVar (Name.fromChars "val")]
        -- Use literal then-branch since "val" is not bound at module level.
        let body = ifExpr [(condition, intExpr 1)] (intExpr 0)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result
    ]

-- MULTIPLE NARROWING TESTS

-- | Tests with multiple guard functions and multiple if-branches.
multipleNarrowingTests :: TestTree
multipleNarrowingTests =
  testGroup
    "multiple narrowings"
    [ testCase "two guards in same module" $ do
        let guard1 = Name.fromChars "isA"
        let guard2 = Name.fromChars "isB"
        let guardMap =
              Map.fromList
                [ (guard1, mkGuardInfo 0 (Can.TType testModuleName (Name.fromChars "A") [])),
                  (guard2, mkGuardInfo 0 (Can.TType testModuleName (Name.fromChars "B") []))
                ]
        let cond1 = callExpr (localVar guard1) [localVar (Name.fromChars "x")]
        let cond2 = callExpr (localVar guard2) [localVar (Name.fromChars "y")]
        let body = ifExpr [(cond1, intExpr 1), (cond2, intExpr 2)] (intExpr 3)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "same guard used in multiple if-expressions" $ do
        let guardName = Name.fromChars "isOk"
        let narrowType = Can.TType testModuleName (Name.fromChars "Ok") []
        let guardMap = singleGuard guardName 0 narrowType
        let cond = callExpr (localVar guardName) [localVar (Name.fromChars "x")]
        let body1 = ifExpr [(cond, intExpr 1)] (intExpr 2)
        let body2 = ifExpr [(cond, intExpr 3)] (intExpr 4)
        let def1 = mkDef (Name.fromChars "a") body1
        let def2 = mkDef (Name.fromChars "b") body2
        let decls = Can.Declare def1 (Can.Declare def2 Can.SaveTheEnvironment)
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "three guards with different narrow types" $ do
        let guardMap =
              Map.fromList
                [ (Name.fromChars "isInt", mkGuardInfo 0 (Can.TType testModuleName (Name.fromChars "Int") [])),
                  (Name.fromChars "isStr", mkGuardInfo 0 (Can.TType testModuleName (Name.fromChars "String") [])),
                  (Name.fromChars "isBool", mkGuardInfo 0 (Can.TType testModuleName (Name.fromChars "Bool") []))
                ]
        let def = mkDef (Name.fromChars "val") (intExpr 42)
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result
    ]

-- TYPE VARIETY TESTS

-- | Tests with different canonical type forms as narrow types,
-- verifying that all type constructors work in the narrowing context.
typeVarietyTests :: TestTree
typeVarietyTests =
  testGroup
    "narrow type varieties"
    [ testCase "TUnit narrow type in module context" $ do
        let guardName = Name.fromChars "isUnit"
        let guardMap = singleGuard guardName 0 Can.TUnit
        let cond = callExpr (localVar guardName) [localVar (Name.fromChars "x")]
        let body = ifExpr [(cond, loc Can.Unit)] (loc Can.Unit)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "TVar narrow type in module context" $ do
        let guardName = Name.fromChars "isGeneric"
        let guardMap = singleGuard guardName 0 (Can.TVar (Name.fromChars "a"))
        let cond = callExpr (localVar guardName) [localVar (Name.fromChars "x")]
        let body = ifExpr [(cond, intExpr 1)] (intExpr 2)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "TTuple narrow type in module context" $ do
        let guardName = Name.fromChars "isPair"
        let narrowType = Can.TTuple (Can.TVar (Name.fromChars "a")) (Can.TVar (Name.fromChars "b")) Nothing
        let guardMap = singleGuard guardName 0 narrowType
        let cond = callExpr (localVar guardName) [localVar (Name.fromChars "x")]
        let body = ifExpr [(cond, intExpr 1)] (intExpr 2)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "TRecord narrow type in module context" $ do
        let guardName = Name.fromChars "isRec"
        let narrowType = Can.TRecord (Map.singleton (Name.fromChars "x") (Can.FieldType 0 (Can.TVar (Name.fromChars "a")))) Nothing
        let guardMap = singleGuard guardName 0 narrowType
        let cond = callExpr (localVar guardName) [localVar (Name.fromChars "r")]
        let body = ifExpr [(cond, intExpr 1)] (intExpr 2)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "TLambda narrow type in module context" $ do
        let guardName = Name.fromChars "isFn"
        let narrowType = Can.TLambda Can.TUnit Can.TUnit
        let guardMap = singleGuard guardName 0 narrowType
        let cond = callExpr (localVar guardName) [localVar (Name.fromChars "f")]
        let body = ifExpr [(cond, intExpr 1)] (intExpr 2)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result,
      testCase "TAlias narrow type in module context" $ do
        let guardName = Name.fromChars "isAlias"
        let narrowType = Can.TAlias testModuleName (Name.fromChars "MyAlias") [(Name.fromChars "a", Can.TVar (Name.fromChars "a"))] (Can.Filled Can.TUnit)
        let guardMap = singleGuard guardName 0 narrowType
        let cond = callExpr (localVar guardName) [localVar (Name.fromChars "val")]
        let body = ifExpr [(cond, intExpr 1)] (intExpr 2)
        let def = mkDef (Name.fromChars "result") body
        let decls = Can.Declare def Can.SaveTheEnvironment
        let canModule = mkModule decls guardMap
        constraint <- Module.constrain canModule
        result <- Solve.run constraint
        assertSolveSuccess result
    ]
