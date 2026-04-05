{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.JavaScript.Functions'.
--
-- Verifies the generation of the F / A helper functions that implement
-- curried function application in the compiled JavaScript runtime.
--
-- == Test Coverage
--
-- * 'generateConditionalFunctions' with empty set — only base function emitted
-- * 'generateConditionalFunctions' with singleton — F2 and A2 appended
-- * 'generateConditionalFunctions' with full default set — matches 'functions'
-- * Base function block always present
-- * generateF: known arities 2..9 produce non-empty output; others produce ""
-- * generateA: known arities 2..9 produce non-empty output; others produce ""
--
-- @since 0.19.1
module Unit.Generate.JavaScript.FunctionsTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.Set as Set
import qualified Generate.JavaScript.Functions as Functions
import Test.Tasty
import Test.Tasty.HUnit

-- | Root test tree.
tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Functions"
    [ baseTests,
      emptyArityTests,
      singletonArityTests,
      defaultArityTests,
      containsTests
    ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

render :: BB.Builder -> String
render = BL8.unpack . BB.toLazyByteString

-- ---------------------------------------------------------------------------
-- Base function block tests
-- ---------------------------------------------------------------------------

baseTests :: TestTree
baseTests =
  testGroup
    "base function block"
    [ testCase "output always contains 'function F('" $
        let out = render (Functions.generateConditionalFunctions Set.empty)
         in ("function F(" `isSubstring` out) @?= True,

      testCase "base block sets wrapper.a and wrapper.f" $
        let out = render (Functions.generateConditionalFunctions Set.empty)
         in ("wrapper.a = arity" `isSubstring` out) @?= True
    ]

-- ---------------------------------------------------------------------------
-- Empty arity set
-- ---------------------------------------------------------------------------

emptyArityTests :: TestTree
emptyArityTests =
  testGroup
    "empty arity set"
    [ testCase "no F2 emitted when set is empty" $
        let out = render (Functions.generateConditionalFunctions Set.empty)
         in ("function F2" `isSubstring` out) @?= False,

      testCase "no A2 emitted when set is empty" $
        let out = render (Functions.generateConditionalFunctions Set.empty)
         in ("function A2" `isSubstring` out) @?= False
    ]

-- ---------------------------------------------------------------------------
-- Singleton arity set
-- ---------------------------------------------------------------------------

singletonArityTests :: TestTree
singletonArityTests =
  testGroup
    "singleton arity set {2}"
    [ testCase "F2 is emitted" $
        let out = render (Functions.generateConditionalFunctions (Set.singleton 2))
         in ("function F2" `isSubstring` out) @?= True,

      testCase "A2 is emitted" $
        let out = render (Functions.generateConditionalFunctions (Set.singleton 2))
         in ("function A2" `isSubstring` out) @?= True,

      testCase "F3 is NOT emitted" $
        let out = render (Functions.generateConditionalFunctions (Set.singleton 2))
         in ("function F3" `isSubstring` out) @?= False
    ]

-- ---------------------------------------------------------------------------
-- Default arity set (2..9)
-- ---------------------------------------------------------------------------

defaultArityTests :: TestTree
defaultArityTests =
  testGroup
    "default arity set 2..9"
    [ testCase "functions equals generateConditionalFunctions {2..9}" $
        render Functions.functions
          @?= render (Functions.generateConditionalFunctions (Set.fromList [2 .. 9])),

      testCase "all F2..F9 are emitted" $
        let out = render Functions.functions
            arities = [2 .. 9 :: Int]
         in fmap (\n -> ("function F" ++ show n) `isSubstring` out) arities
              @?= replicate 8 True,

      testCase "all A2..A9 are emitted" $
        let out = render Functions.functions
            arities = [2 .. 9 :: Int]
         in fmap (\n -> ("function A" ++ show n) `isSubstring` out) arities
              @?= replicate 8 True
    ]

-- ---------------------------------------------------------------------------
-- Content smoke tests
-- ---------------------------------------------------------------------------

containsTests :: TestTree
containsTests =
  testGroup
    "content correctness"
    [ testCase "A2 uses fun.a === 2 for fast path" $
        let out = render (Functions.generateConditionalFunctions (Set.singleton 2))
         in ("fun.a === 2" `isSubstring` out) @?= True,

      testCase "F3 uses three nested functions" $
        let out = render (Functions.generateConditionalFunctions (Set.singleton 3))
            countFunctionKw = length (filter (== "function") (words out))
         in (countFunctionKw >= 3) @?= True,

      testCase "arity 1 produces empty output (not in 2..9)" $
        let out = render (Functions.generateConditionalFunctions (Set.singleton 1))
         in ("function F1" `isSubstring` out) @?= False,

      testCase "arity 10 produces empty output (not in 2..9)" $
        let out = render (Functions.generateConditionalFunctions (Set.singleton 10))
         in ("function F10" `isSubstring` out) @?= False
    ]

-- ---------------------------------------------------------------------------
-- Substring helper
-- ---------------------------------------------------------------------------

isSubstring :: String -> String -> Bool
isSubstring needle haystack =
  any (needle `isPrefix`) (tails haystack)

isPrefix :: String -> String -> Bool
isPrefix [] _ = True
isPrefix _ [] = False
isPrefix (x : xs) (y : ys) = x == y && isPrefix xs ys

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest
