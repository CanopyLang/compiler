module Unit.Data.NameTest (tests) where

import qualified Data.Name as Name
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Data.Name Tests"
    [ testFromChars,
      testToChars,
      testHasDot,
      testSplitDots,
      testKernelFunctions,
      testTypeChecking
    ]

testFromChars :: TestTree
testFromChars =
  testGroup
    "fromChars tests"
    [ testCase "simple name" $ do
        let name = Name.fromChars "hello"
        Name.toChars name @?= "hello",
      testCase "empty name" $ do
        let name = Name.fromChars ""
        Name.toChars name @?= "",
      testCase "name with dots" $ do
        let name = Name.fromChars "Module.function"
        Name.toChars name @?= "Module.function"
    ]

testToChars :: TestTree
testToChars =
  testGroup
    "toChars tests"
    [ testCase "roundtrip conversion" $ do
        let original = "testName123"
        let name = Name.fromChars original
        Name.toChars name @?= original
    ]

testHasDot :: TestTree
testHasDot =
  testGroup
    "hasDot tests"
    [ testCase "name without dot" $ do
        let name = Name.fromChars "simple"
        Name.hasDot name @?= False,
      testCase "name with dot" $ do
        let name = Name.fromChars "Module.function"
        Name.hasDot name @?= True,
      testCase "name with multiple dots" $ do
        let name = Name.fromChars "Module.Sub.function"
        Name.hasDot name @?= True
    ]

testSplitDots :: TestTree
testSplitDots =
  testGroup
    "splitDots tests"
    [ testCase "simple name" $ do
        let name = Name.fromChars "simple"
        Name.splitDots name @?= ["simple"],
      testCase "qualified name" $ do
        let name = Name.fromChars "Module.function"
        Name.splitDots name @?= ["Module", "function"],
      testCase "deeply qualified name" $ do
        let name = Name.fromChars "A.B.C.function"
        Name.splitDots name @?= ["A", "B", "C", "function"]
    ]

testKernelFunctions :: TestTree
testKernelFunctions =
  testGroup
    "kernel function tests"
    [ testCase "kernel name detection" $ do
        let kernelName = Name.fromChars "Canopy.Kernel.List.cons"
        Name.isKernel kernelName @?= True,
      testCase "non-kernel name detection" $ do
        let regularName = Name.fromChars "List.cons"
        Name.isKernel regularName @?= False
    ]

testTypeChecking :: TestTree
testTypeChecking =
  testGroup
    "type checking functions"
    [ testCase "number types" $ do
        let numberName = Name.fromChars "number"
        let numberVarName = Name.fromChars "numberVar"
        let intName = Name.fromChars "Int"

        Name.isNumberType numberName @?= True
        Name.isNumberType numberVarName @?= True
        Name.isNumberType intName @?= False,
      testCase "comparable types" $ do
        let comparableName = Name.fromChars "comparable"
        let comparableVarName = Name.fromChars "comparableVar"
        let intName = Name.fromChars "Int"

        Name.isComparableType comparableName @?= True
        Name.isComparableType comparableVarName @?= True
        Name.isComparableType intName @?= False,
      testCase "appendable types" $ do
        let appendableName = Name.fromChars "appendable"
        let appendableVarName = Name.fromChars "appendableVar"
        let intName = Name.fromChars "Int"

        Name.isAppendableType appendableName @?= True
        Name.isAppendableType appendableVarName @?= True
        Name.isAppendableType intName @?= False
    ]
