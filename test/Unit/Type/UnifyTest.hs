{-# LANGUAGE OverloadedStrings #-}

-- | Comprehensive test suite for the Type.Unify module.
--
-- Tests cover the full range of unification scenarios including flex variables,
-- rigid variables, super types, structures (App1, Fun1, Record1, Tuple1, Unit1,
-- EmptyRecord1), and various error/mismatch conditions. Each test creates fresh
-- type variables via IO to ensure isolation.
--
-- @since 0.19.2
module Unit.Type.UnifyTest (tests) where

import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import Test.Tasty
import Test.Tasty.HUnit
import qualified Type.Unify as Unify
import Type.Unify (Answer (..))
import qualified Type.Type as Type
import Type.Type
  ( Content (..),
    Descriptor (Descriptor),
    FlatType (..),
    SuperType (..),
    Variable,
    noMark,
    noRank,
  )
import qualified Type.UnionFind as UF

-- HELPERS

-- | Create a variable whose content is a given FlatType structure.
mkStructureVar :: FlatType -> IO Variable
mkStructureVar ft =
  UF.fresh (Descriptor (Structure ft) noRank noMark Nothing)

-- | Create a variable representing the Int type (Basics.Int).
mkIntVar :: IO Variable
mkIntVar =
  mkStructureVar (App1 ModuleName.basics Name.int [])

-- | Create a variable representing the Float type (Basics.Float).
mkFloatVar :: IO Variable
mkFloatVar =
  mkStructureVar (App1 ModuleName.basics Name.float [])

-- | Create a variable representing the String type (String.String).
mkStringVar :: IO Variable
mkStringVar =
  mkStructureVar (App1 ModuleName.string Name.string [])

-- | Create a variable representing the Char type (Char.Char).
mkCharVar :: IO Variable
mkCharVar =
  mkStructureVar (App1 ModuleName.char Name.char [])

-- | Create a variable representing the Bool type (Basics.Bool).
mkBoolVar :: IO Variable
mkBoolVar =
  mkStructureVar (App1 ModuleName.basics Name.bool [])

-- | Check whether a unification Answer is Ok.
isOk :: Answer -> Bool
isOk (Ok _) = True
isOk (Err _ _ _) = False

-- | Check whether a unification Answer is Err.
isErr :: Answer -> Bool
isErr = not . isOk

-- TESTS

tests :: TestTree
tests =
  testGroup
    "Type.Unify Tests"
    [ flexVarTests,
      structureTests,
      funTests,
      recordTests,
      rigidVarTests,
      flexSuperTests,
      selfUnificationTests,
      unitAndEmptyRecordTests,
      tupleTests,
      equivalenceAfterUnifyTests,
      sequentialUnifyTests,
      nestedStructureTests
    ]

-- FLEX VAR TESTS

flexVarTests :: TestTree
flexVarTests =
  testGroup
    "flex variable unification"
    [ testCase "two fresh flex vars unify to Ok" $ do
        v1 <- Type.mkFlexVar
        v2 <- Type.mkFlexVar
        answer <- Unify.unify v1 v2
        assertBool "expected Ok for two flex vars" (isOk answer),
      testCase "flex var unifies with structure (becomes that structure)" $ do
        flex <- Type.mkFlexVar
        intV <- mkIntVar
        answer <- Unify.unify flex intV
        assertBool "expected Ok for flex + structure" (isOk answer)
        desc <- UF.get flex
        assertStructureIsInt desc,
      testCase "named flex var unifies with unnamed flex var" $ do
        named <- Type.nameToFlex "a"
        unnamed <- Type.mkFlexVar
        answer <- Unify.unify named unnamed
        assertBool "expected Ok for named flex + unnamed flex" (isOk answer)
    ]

-- | Assert that a descriptor's content is the Int structure.
assertStructureIsInt :: Descriptor -> IO ()
assertStructureIsInt (Descriptor content _ _ _) =
  assertContentIsApp "Int" content

-- | Assert that content is an App1 with the given type name.
assertContentIsApp :: String -> Content -> IO ()
assertContentIsApp expected (Structure (App1 _ name _)) =
  Name.toChars name @?= expected
assertContentIsApp expected _ =
  assertFailure ("expected App1 " ++ expected ++ " but got different content")

-- STRUCTURE TESTS

structureTests :: TestTree
structureTests =
  testGroup
    "structure unification"
    [ testCase "identical App1 structures unify" $ do
        int1 <- mkIntVar
        int2 <- mkIntVar
        answer <- Unify.unify int1 int2
        assertBool "expected Ok for identical App1" (isOk answer),
      testCase "mismatched App1 names fail" $ do
        intV <- mkIntVar
        floatV <- mkFloatVar
        answer <- Unify.unify intV floatV
        assertBool "expected Err for Int vs Float" (isErr answer),
      testCase "mismatched App1 homes fail" $ do
        v1 <- mkStructureVar (App1 ModuleName.basics "MyType" [])
        v2 <- mkStructureVar (App1 ModuleName.string "MyType" [])
        answer <- Unify.unify v1 v2
        assertBool "expected Err for different module homes" (isErr answer),
      testCase "App1 with matching type args unifies" $ do
        arg1 <- Type.mkFlexVar
        arg2 <- Type.mkFlexVar
        v1 <- mkStructureVar (App1 ModuleName.list Name.list [arg1])
        v2 <- mkStructureVar (App1 ModuleName.list Name.list [arg2])
        answer <- Unify.unify v1 v2
        assertBool "expected Ok for List a ~ List b" (isOk answer),
      testCase "App1 with mismatched arg count fails" $ do
        arg1 <- Type.mkFlexVar
        v1 <- mkStructureVar (App1 ModuleName.basics "Pair" [arg1])
        v2 <- mkStructureVar (App1 ModuleName.basics "Pair" [])
        answer <- Unify.unify v1 v2
        assertBool "expected Err for different arg counts" (isErr answer)
    ]

-- FUN TESTS

funTests :: TestTree
funTests =
  testGroup
    "function type unification"
    [ testCase "Fun1 a b unifies with Fun1 c d" $ do
        a <- Type.mkFlexVar
        b <- Type.mkFlexVar
        c <- Type.mkFlexVar
        d <- Type.mkFlexVar
        fun1 <- mkStructureVar (Fun1 a b)
        fun2 <- mkStructureVar (Fun1 c d)
        answer <- Unify.unify fun1 fun2
        assertBool "expected Ok for Fun1 unification" (isOk answer)
        eqAC <- UF.equivalent a c
        assertBool "arg vars should be equivalent after unification" eqAC
        eqBD <- UF.equivalent b d
        assertBool "result vars should be equivalent after unification" eqBD,
      testCase "Fun1 with nested structures unifies" $ do
        intA <- mkIntVar
        stringA <- mkStringVar
        intB <- mkIntVar
        stringB <- mkStringVar
        fun1 <- mkStructureVar (Fun1 intA stringA)
        fun2 <- mkStructureVar (Fun1 intB stringB)
        answer <- Unify.unify fun1 fun2
        assertBool "expected Ok for (Int -> String) ~ (Int -> String)" (isOk answer),
      testCase "Fun1 with mismatched arg types fails" $ do
        intV <- mkIntVar
        stringV <- mkStringVar
        flex1 <- Type.mkFlexVar
        flex2 <- Type.mkFlexVar
        fun1 <- mkStructureVar (Fun1 intV flex1)
        fun2 <- mkStructureVar (Fun1 stringV flex2)
        answer <- Unify.unify fun1 fun2
        assertBool "expected Err for (Int -> a) ~ (String -> b)" (isErr answer)
    ]

-- RECORD TESTS

recordTests :: TestTree
recordTests =
  testGroup
    "record unification"
    [ testCase "matching fields unify" $ do
        xVal1 <- mkIntVar
        yVal1 <- mkStringVar
        xVal2 <- mkIntVar
        yVal2 <- mkStringVar
        ext1 <- mkStructureVar EmptyRecord1
        ext2 <- mkStructureVar EmptyRecord1
        let fields1 = Map.fromList [("x", xVal1), ("y", yVal1)]
        let fields2 = Map.fromList [("x", xVal2), ("y", yVal2)]
        rec1 <- mkStructureVar (Record1 fields1 ext1)
        rec2 <- mkStructureVar (Record1 fields2 ext2)
        answer <- Unify.unify rec1 rec2
        assertBool "expected Ok for matching record fields" (isOk answer),
      testCase "extra fields on one side with extension var" $ do
        xVal1 <- mkIntVar
        yVal1 <- mkStringVar
        xVal2 <- mkIntVar
        ext1 <- mkStructureVar EmptyRecord1
        ext2 <- Type.mkFlexVar
        let fields1 = Map.fromList [("x", xVal1), ("y", yVal1)]
        let fields2 = Map.fromList [("x", xVal2)]
        rec1 <- mkStructureVar (Record1 fields1 ext1)
        rec2 <- mkStructureVar (Record1 fields2 ext2)
        answer <- Unify.unify rec1 rec2
        assertBool "expected Ok when extension var absorbs extra fields" (isOk answer),
      testCase "mismatched field types fail" $ do
        xInt <- mkIntVar
        xString <- mkStringVar
        ext1 <- mkStructureVar EmptyRecord1
        ext2 <- mkStructureVar EmptyRecord1
        let fields1 = Map.fromList [("x", xInt)]
        let fields2 = Map.fromList [("x", xString)]
        rec1 <- mkStructureVar (Record1 fields1 ext1)
        rec2 <- mkStructureVar (Record1 fields2 ext2)
        answer <- Unify.unify rec1 rec2
        assertBool "expected Err for mismatched field types" (isErr answer)
    ]

-- RIGID VAR TESTS

rigidVarTests :: TestTree
rigidVarTests =
  testGroup
    "rigid variable unification"
    [ testCase "rigid var unifies with same-name rigid var" $ do
        r1 <- Type.nameToRigid "a"
        r2 <- Type.nameToRigid "a"
        answer <- Unify.unify r1 r2
        assertBool "expected Ok for same-name rigid vars" (isOk answer),
      testCase "rigid var fails with different-name rigid var" $ do
        r1 <- Type.nameToRigid "a"
        r2 <- Type.nameToRigid "b"
        answer <- Unify.unify r1 r2
        assertBool "expected Err for different-name rigid vars" (isErr answer),
      testCase "rigid var fails with structure" $ do
        r <- Type.nameToRigid "a"
        intV <- mkIntVar
        answer <- Unify.unify r intV
        assertBool "expected Err for rigid var vs structure" (isErr answer),
      testCase "rigid var unifies with flex var" $ do
        r <- Type.nameToRigid "a"
        f <- Type.mkFlexVar
        answer <- Unify.unify r f
        assertBool "expected Ok for rigid var + flex var" (isOk answer)
    ]

-- FLEX SUPER TESTS

flexSuperTests :: TestTree
flexSuperTests =
  testGroup
    "flex super type unification"
    [ testCase "FlexSuper Number unifies with Int" $ do
        numVar <- Type.mkFlexNumber
        intV <- mkIntVar
        answer <- Unify.unify numVar intV
        assertBool "expected Ok for number ~ Int" (isOk answer),
      testCase "FlexSuper Number unifies with Float" $ do
        numVar <- Type.mkFlexNumber
        floatV <- mkFloatVar
        answer <- Unify.unify numVar floatV
        assertBool "expected Ok for number ~ Float" (isOk answer),
      testCase "FlexSuper Number fails with String" $ do
        numVar <- Type.mkFlexNumber
        stringV <- mkStringVar
        answer <- Unify.unify numVar stringV
        assertBool "expected Err for number ~ String" (isErr answer),
      testCase "FlexSuper Number fails with Bool" $ do
        numVar <- Type.mkFlexNumber
        boolV <- mkBoolVar
        answer <- Unify.unify numVar boolV
        assertBool "expected Err for number ~ Bool" (isErr answer),
      testCase "FlexSuper Comparable unifies with Int" $ do
        compVar <- mkFlexSuperVar Comparable
        intV <- mkIntVar
        answer <- Unify.unify compVar intV
        assertBool "expected Ok for comparable ~ Int" (isOk answer),
      testCase "FlexSuper Comparable unifies with Float" $ do
        compVar <- mkFlexSuperVar Comparable
        floatV <- mkFloatVar
        answer <- Unify.unify compVar floatV
        assertBool "expected Ok for comparable ~ Float" (isOk answer),
      testCase "FlexSuper Comparable unifies with String" $ do
        compVar <- mkFlexSuperVar Comparable
        stringV <- mkStringVar
        answer <- Unify.unify compVar stringV
        assertBool "expected Ok for comparable ~ String" (isOk answer),
      testCase "FlexSuper Comparable unifies with Char" $ do
        compVar <- mkFlexSuperVar Comparable
        charV <- mkCharVar
        answer <- Unify.unify compVar charV
        assertBool "expected Ok for comparable ~ Char" (isOk answer),
      testCase "FlexSuper Appendable unifies with String" $ do
        appVar <- mkFlexSuperVar Appendable
        stringV <- mkStringVar
        answer <- Unify.unify appVar stringV
        assertBool "expected Ok for appendable ~ String" (isOk answer),
      testCase "FlexSuper Appendable fails with Int" $ do
        appVar <- mkFlexSuperVar Appendable
        intV <- mkIntVar
        answer <- Unify.unify appVar intV
        assertBool "expected Err for appendable ~ Int" (isErr answer),
      testCase "FlexSuper Appendable unifies with List a" $ do
        appVar <- mkFlexSuperVar Appendable
        elemVar <- Type.mkFlexVar
        listV <- mkStructureVar (App1 ModuleName.list Name.list [elemVar])
        answer <- Unify.unify appVar listV
        assertBool "expected Ok for appendable ~ List a" (isOk answer),
      testCase "FlexSuper Number unifies with FlexSuper Number" $ do
        n1 <- Type.mkFlexNumber
        n2 <- Type.mkFlexNumber
        answer <- Unify.unify n1 n2
        assertBool "expected Ok for number ~ number" (isOk answer),
      testCase "FlexSuper Number fails with FlexSuper Appendable" $ do
        numVar <- Type.mkFlexNumber
        appVar <- mkFlexSuperVar Appendable
        answer <- Unify.unify numVar appVar
        assertBool "expected Err for number ~ appendable" (isErr answer),
      testCase "FlexSuper Comparable unifies with FlexSuper Number" $ do
        compVar <- mkFlexSuperVar Comparable
        numVar <- Type.mkFlexNumber
        answer <- Unify.unify compVar numVar
        assertBool "expected Ok for comparable ~ number" (isOk answer)
    ]

-- | Create a FlexSuper variable with the given super type.
mkFlexSuperVar :: SuperType -> IO Variable
mkFlexSuperVar super =
  UF.fresh (Descriptor (FlexSuper super Nothing) noRank noMark Nothing)

-- SELF UNIFICATION TESTS

selfUnificationTests :: TestTree
selfUnificationTests =
  testGroup
    "self unification"
    [ testCase "flex var unifies with self" $ do
        v <- Type.mkFlexVar
        answer <- Unify.unify v v
        assertBool "expected Ok for self-unification" (isOk answer),
      testCase "structure var unifies with self" $ do
        intV <- mkIntVar
        answer <- Unify.unify intV intV
        assertBool "expected Ok for structure self-unification" (isOk answer)
    ]

-- UNIT AND EMPTY RECORD TESTS

unitAndEmptyRecordTests :: TestTree
unitAndEmptyRecordTests =
  testGroup
    "Unit1 and EmptyRecord1 unification"
    [ testCase "EmptyRecord1 unifies with EmptyRecord1" $ do
        r1 <- mkStructureVar EmptyRecord1
        r2 <- mkStructureVar EmptyRecord1
        answer <- Unify.unify r1 r2
        assertBool "expected Ok for EmptyRecord1 ~ EmptyRecord1" (isOk answer),
      testCase "Unit1 unifies with Unit1" $ do
        u1 <- mkStructureVar Unit1
        u2 <- mkStructureVar Unit1
        answer <- Unify.unify u1 u2
        assertBool "expected Ok for Unit1 ~ Unit1" (isOk answer),
      testCase "Unit1 fails with EmptyRecord1" $ do
        u <- mkStructureVar Unit1
        r <- mkStructureVar EmptyRecord1
        answer <- Unify.unify u r
        assertBool "expected Err for Unit1 vs EmptyRecord1" (isErr answer),
      testCase "Unit1 fails with Int" $ do
        u <- mkStructureVar Unit1
        intV <- mkIntVar
        answer <- Unify.unify u intV
        assertBool "expected Err for Unit1 vs Int" (isErr answer)
    ]

-- TUPLE TESTS

tupleTests :: TestTree
tupleTests =
  testGroup
    "tuple unification"
    [ testCase "matching 2-element tuples unify" $ do
        a1 <- mkIntVar
        b1 <- mkStringVar
        a2 <- mkIntVar
        b2 <- mkStringVar
        t1 <- mkStructureVar (Tuple1 a1 b1 Nothing)
        t2 <- mkStructureVar (Tuple1 a2 b2 Nothing)
        answer <- Unify.unify t1 t2
        assertBool "expected Ok for (Int, String) ~ (Int, String)" (isOk answer),
      testCase "matching 3-element tuples unify" $ do
        a1 <- mkIntVar
        b1 <- mkStringVar
        c1 <- mkBoolVar
        a2 <- mkIntVar
        b2 <- mkStringVar
        c2 <- mkBoolVar
        t1 <- mkStructureVar (Tuple1 a1 b1 (Just c1))
        t2 <- mkStructureVar (Tuple1 a2 b2 (Just c2))
        answer <- Unify.unify t1 t2
        assertBool "expected Ok for (Int, String, Bool) ~ (Int, String, Bool)" (isOk answer),
      testCase "2-tuple vs 3-tuple fails" $ do
        a1 <- mkIntVar
        b1 <- mkStringVar
        a2 <- mkIntVar
        b2 <- mkStringVar
        c2 <- mkBoolVar
        t1 <- mkStructureVar (Tuple1 a1 b1 Nothing)
        t2 <- mkStructureVar (Tuple1 a2 b2 (Just c2))
        answer <- Unify.unify t1 t2
        assertBool "expected Err for 2-tuple vs 3-tuple" (isErr answer),
      testCase "tuple with mismatched element types fails" $ do
        a1 <- mkIntVar
        b1 <- mkStringVar
        a2 <- mkStringVar
        b2 <- mkIntVar
        t1 <- mkStructureVar (Tuple1 a1 b1 Nothing)
        t2 <- mkStructureVar (Tuple1 a2 b2 Nothing)
        answer <- Unify.unify t1 t2
        assertBool "expected Err for (Int, String) vs (String, Int)" (isErr answer),
      testCase "tuple with flex var elements unifies" $ do
        a <- Type.mkFlexVar
        b <- Type.mkFlexVar
        c <- mkIntVar
        d <- mkStringVar
        t1 <- mkStructureVar (Tuple1 a b Nothing)
        t2 <- mkStructureVar (Tuple1 c d Nothing)
        answer <- Unify.unify t1 t2
        assertBool "expected Ok for (a, b) ~ (Int, String)" (isOk answer)
    ]

-- EQUIVALENCE AFTER UNIFY TESTS

equivalenceAfterUnifyTests :: TestTree
equivalenceAfterUnifyTests =
  testGroup
    "equivalence after unification"
    [ testCase "flex vars become equivalent after Ok unification" $ do
        v1 <- Type.mkFlexVar
        v2 <- Type.mkFlexVar
        eqBefore <- UF.equivalent v1 v2
        assertBool "should not be equivalent before unification" (not eqBefore)
        answer <- Unify.unify v1 v2
        assertBool "expected Ok" (isOk answer)
        eqAfter <- UF.equivalent v1 v2
        assertBool "should be equivalent after unification" eqAfter,
      testCase "flex var and structure become equivalent after Ok" $ do
        flex <- Type.mkFlexVar
        intV <- mkIntVar
        answer <- Unify.unify flex intV
        assertBool "expected Ok" (isOk answer)
        eq <- UF.equivalent flex intV
        assertBool "flex and structure should be equivalent" eq,
      testCase "variables remain non-equivalent after Err" $ do
        r1 <- Type.nameToRigid "a"
        r2 <- Type.nameToRigid "b"
        answer <- Unify.unify r1 r2
        assertBool "expected Err" (isErr answer)
        eq <- UF.equivalent r1 r2
        assertBool "rigid vars should not be equivalent after Err" (not eq)
    ]

-- SEQUENTIAL UNIFY TESTS

sequentialUnifyTests :: TestTree
sequentialUnifyTests =
  testGroup
    "multiple sequential unifications"
    [ testCase "chain of flex var unifications" $ do
        a <- Type.mkFlexVar
        b <- Type.mkFlexVar
        c <- Type.mkFlexVar
        ans1 <- Unify.unify a b
        assertBool "a ~ b should be Ok" (isOk ans1)
        ans2 <- Unify.unify b c
        assertBool "b ~ c should be Ok" (isOk ans2)
        eqAC <- UF.equivalent a c
        assertBool "a and c should be equivalent via b" eqAC,
      testCase "flex var chain then structure" $ do
        a <- Type.mkFlexVar
        b <- Type.mkFlexVar
        intV <- mkIntVar
        ans1 <- Unify.unify a b
        assertBool "a ~ b should be Ok" (isOk ans1)
        ans2 <- Unify.unify b intV
        assertBool "b ~ Int should be Ok" (isOk ans2)
        eqAInt <- UF.equivalent a intV
        assertBool "a should be equivalent to Int after chain" eqAInt,
      testCase "conflicting sequential unification fails" $ do
        a <- Type.mkFlexVar
        intV <- mkIntVar
        stringV <- mkStringVar
        ans1 <- Unify.unify a intV
        assertBool "a ~ Int should be Ok" (isOk ans1)
        ans2 <- Unify.unify a stringV
        assertBool "a ~ String should be Err after a ~ Int" (isErr ans2)
    ]

-- NESTED STRUCTURE TESTS

nestedStructureTests :: TestTree
nestedStructureTests =
  testGroup
    "nested structure unification"
    [ testCase "Fun1 with nested App1 structures" $ do
        intA <- mkIntVar
        intB <- mkIntVar
        strA <- mkStringVar
        strB <- mkStringVar
        inner1 <- mkStructureVar (Fun1 intA strA)
        inner2 <- mkStructureVar (Fun1 intB strB)
        boolA <- mkBoolVar
        boolB <- mkBoolVar
        outer1 <- mkStructureVar (Fun1 inner1 boolA)
        outer2 <- mkStructureVar (Fun1 inner2 boolB)
        answer <- Unify.unify outer1 outer2
        assertBool "expected Ok for ((Int -> String) -> Bool) ~ ((Int -> String) -> Bool)" (isOk answer),
      testCase "List of Int unifies with List of Int" $ do
        int1 <- mkIntVar
        int2 <- mkIntVar
        list1 <- mkStructureVar (App1 ModuleName.list Name.list [int1])
        list2 <- mkStructureVar (App1 ModuleName.list Name.list [int2])
        answer <- Unify.unify list1 list2
        assertBool "expected Ok for List Int ~ List Int" (isOk answer),
      testCase "List of Int fails with List of String" $ do
        intV <- mkIntVar
        stringV <- mkStringVar
        list1 <- mkStructureVar (App1 ModuleName.list Name.list [intV])
        list2 <- mkStructureVar (App1 ModuleName.list Name.list [stringV])
        answer <- Unify.unify list1 list2
        assertBool "expected Err for List Int vs List String" (isErr answer),
      testCase "Fun1 returning a tuple unifies correctly" $ do
        a1 <- mkIntVar
        b1 <- mkStringVar
        c1 <- mkBoolVar
        tup1 <- mkStructureVar (Tuple1 b1 c1 Nothing)
        fun1 <- mkStructureVar (Fun1 a1 tup1)
        a2 <- mkIntVar
        b2 <- mkStringVar
        c2 <- mkBoolVar
        tup2 <- mkStructureVar (Tuple1 b2 c2 Nothing)
        fun2 <- mkStructureVar (Fun1 a2 tup2)
        answer <- Unify.unify fun1 fun2
        assertBool "expected Ok for (Int -> (String, Bool)) ~ (Int -> (String, Bool))" (isOk answer)
    ]
