{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.ExpressionCallTest - Tests for call code generation
--
-- This module provides unit tests for the pure helper functions exported by
-- "Generate.JavaScript.Expression.Call". The focus is on functions that
-- operate entirely on 'JS.Expr' values and require no complex monadic context.
--
-- == Test Coverage
--
-- * isLiteral: identifies String, Float, Int, Bool as literals
-- * isStringLiteral: only String expressions qualify
-- * strictEq: special-cases 0 and Bool for compact output
-- * strictNEq: special-cases 0 and Bool for compact output
-- * equal: delegates to strictEq for literals, wraps utils.eq otherwise
-- * notEqual: delegates to strictNEq for literals, wraps !utils.eq otherwise
-- * generateNormalCall: single-arg uses curried call; 2..9 args use A-helpers
-- * generateTupleCall: Tuple.first / Tuple.second optimise to field access
-- * generateJsArrayCall: singleton and unsafeGet optimise to native JS
-- * generateBitwiseCall: complement/and/or/xor/shift optimise to native JS
-- * jsAppend: always wraps utils.ap
--
-- @since 0.19.1
module Unit.Generate.JavaScript.ExpressionCallTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression.Call as Call
import qualified Generate.JavaScript.Name as JsName

-- | Root test tree for Generate.JavaScript.Expression.Call.
tests :: TestTree
tests = testGroup "Generate.JavaScript.Expression.Call Tests"
  [ isLiteralTests
  , isStringLiteralTests
  , strictEqTests
  , strictNEqTests
  , equalTests
  , notEqualTests
  , generateNormalCallTests
  , generateTupleCallTests
  , generateJsArrayCallTests
  , generateBitwiseCallTests
  , jsAppendTests
  , cmpTests
  , callHelpersTests
  , generateGlobalCallTests
  , toSeqsTests
  ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Reused JS.Expr fixtures.
litInt :: JS.Expr
litInt = JS.Int 7

litStr :: JS.Expr
litStr = JS.String "hello"

litFloat :: JS.Expr
litFloat = JS.Float "3.14"

litBoolTrue :: JS.Expr
litBoolTrue = JS.Bool True

litBoolFalse :: JS.Expr
litBoolFalse = JS.Bool False

refX :: JS.Expr
refX = JS.Ref (JsName.fromLocal (Name.fromChars "x"))

refY :: JS.Expr
refY = JS.Ref (JsName.fromLocal (Name.fromChars "y"))

basicsHome :: ModuleName.Canonical
basicsHome = ModuleName.basics

-- ---------------------------------------------------------------------------
-- isLiteral
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.isLiteral'.
isLiteralTests :: TestTree
isLiteralTests = testGroup "isLiteral"
  [ testCase "JS.Int is a literal" $
      Call.isLiteral (JS.Int 0) @?= True

  , testCase "JS.Float is a literal" $
      Call.isLiteral litFloat @?= True

  , testCase "JS.String is a literal" $
      Call.isLiteral litStr @?= True

  , testCase "JS.Bool True is a literal" $
      Call.isLiteral litBoolTrue @?= True

  , testCase "JS.Bool False is a literal" $
      Call.isLiteral litBoolFalse @?= True

  , testCase "JS.Ref is not a literal" $
      Call.isLiteral refX @?= False

  , testCase "JS.Array is not a literal" $
      Call.isLiteral (JS.Array []) @?= False

  , testCase "JS.Null is not a literal" $
      Call.isLiteral JS.Null @?= False
  ]

-- ---------------------------------------------------------------------------
-- isStringLiteral
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.isStringLiteral'.
isStringLiteralTests :: TestTree
isStringLiteralTests = testGroup "isStringLiteral"
  [ testCase "JS.String is a string literal" $
      Call.isStringLiteral litStr @?= True

  , testCase "JS.Int is not a string literal" $
      Call.isStringLiteral litInt @?= False

  , testCase "JS.Float is not a string literal" $
      Call.isStringLiteral litFloat @?= False

  , testCase "JS.Bool is not a string literal" $
      Call.isStringLiteral litBoolTrue @?= False
  ]

-- ---------------------------------------------------------------------------
-- strictEq
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.strictEq'.
--
-- strictEq short-circuits when either side is Int 0 or Bool to avoid
-- emitting the === operator.
strictEqTests :: TestTree
strictEqTests = testGroup "strictEq"
  [ testCase "Int 0 on left produces PrefixNot of right" $
      let result = Call.strictEq (JS.Int 0) refY
      in case result of
           JS.Prefix JS.PrefixNot _ -> pure ()
           other -> assertFailure ("Expected PrefixNot, got: " ++ show other)

  , testCase "Int 0 on right produces PrefixNot of left" $
      let result = Call.strictEq refX (JS.Int 0)
      in case result of
           JS.Prefix JS.PrefixNot _ -> pure ()
           other -> assertFailure ("Expected PrefixNot, got: " ++ show other)

  , testCase "Bool True on left returns right unchanged" $
      show (Call.strictEq litBoolTrue refY) @?= show refY

  , testCase "Bool False on left produces PrefixNot of right" $
      let result = Call.strictEq litBoolFalse refY
      in case result of
           JS.Prefix JS.PrefixNot _ -> pure ()
           other -> assertFailure ("Expected PrefixNot, got: " ++ show other)

  , testCase "Bool True on right returns left unchanged" $
      show (Call.strictEq refX litBoolTrue) @?= show refX

  , testCase "Bool False on right produces PrefixNot of left" $
      let result = Call.strictEq refX litBoolFalse
      in case result of
           JS.Prefix JS.PrefixNot _ -> pure ()
           other -> assertFailure ("Expected PrefixNot, got: " ++ show other)

  , testCase "two non-special exprs produce OpEq Infix" $
      let result = Call.strictEq litInt litStr
      in case result of
           JS.Infix JS.OpEq _ _ -> pure ()
           other -> assertFailure ("Expected OpEq Infix, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- strictNEq
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.strictNEq'.
strictNEqTests :: TestTree
strictNEqTests = testGroup "strictNEq"
  [ testCase "Int 0 on left produces double PrefixNot" $
      let result = Call.strictNEq (JS.Int 0) refY
      in case result of
           JS.Prefix JS.PrefixNot (JS.Prefix JS.PrefixNot _) -> pure ()
           other -> assertFailure ("Expected !!expr, got: " ++ show other)

  , testCase "Int 0 on right produces double PrefixNot" $
      let result = Call.strictNEq refX (JS.Int 0)
      in case result of
           JS.Prefix JS.PrefixNot (JS.Prefix JS.PrefixNot _) -> pure ()
           other -> assertFailure ("Expected !!expr, got: " ++ show other)

  , testCase "Bool True on left produces PrefixNot of right" $
      let result = Call.strictNEq litBoolTrue refY
      in case result of
           JS.Prefix JS.PrefixNot _ -> pure ()
           other -> assertFailure ("Expected PrefixNot, got: " ++ show other)

  , testCase "Bool False on left returns right unchanged" $
      show (Call.strictNEq litBoolFalse refY) @?= show refY

  , testCase "two non-special exprs produce OpNe Infix" $
      let result = Call.strictNEq litInt litStr
      in case result of
           JS.Infix JS.OpNe _ _ -> pure ()
           other -> assertFailure ("Expected OpNe Infix, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- equal
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.equal'.
--
-- For literals, equal delegates to strictEq. For non-literals it emits
-- a JS.Call to utils_eq.
equalTests :: TestTree
equalTests = testGroup "equal"
  [ testCase "equal with two Int literals produces strict-eq form (not Call)" $
      let result = Call.equal (JS.Int 1) (JS.Int 2)
      in case result of
           JS.Call _ _ -> assertFailure "Should not emit a Call for two literals"
           _ -> pure ()

  , testCase "equal with two Refs produces JS.Call" $
      let result = Call.equal refX refY
      in case result of
           JS.Call _ _ -> pure ()
           other -> assertFailure ("Expected JS.Call for non-literals, got: " ++ show other)

  , testCase "equal with left literal produces strict-eq form" $
      let result = Call.equal litInt refY
      in case result of
           JS.Call _ _ -> assertFailure "Should not emit a Call when left is literal"
           _ -> pure ()

  , testCase "equal with right literal produces strict-eq form" $
      let result = Call.equal refX litStr
      in case result of
           JS.Call _ _ -> assertFailure "Should not emit a Call when right is literal"
           _ -> pure ()
  ]

-- ---------------------------------------------------------------------------
-- notEqual
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.notEqual'.
notEqualTests :: TestTree
notEqualTests = testGroup "notEqual"
  [ testCase "notEqual with two Int literals does not produce JS.Call" $
      let result = Call.notEqual (JS.Int 1) (JS.Int 2)
      in case result of
           JS.Call _ _ -> assertFailure "Should not emit a Call for two literals"
           _ -> pure ()

  , testCase "notEqual with two Refs produces negated JS.Call" $
      let result = Call.notEqual refX refY
      in case result of
           JS.Prefix JS.PrefixNot (JS.Call _ _) -> pure ()
           other -> assertFailure ("Expected !utils_eq(...), got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- generateNormalCall
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.generateNormalCall'.
generateNormalCallTests :: TestTree
generateNormalCallTests = testGroup "generateNormalCall"
  [ testCase "zero args produces curried call (JS.Call func [])" $
      let result = Call.generateNormalCall refX []
      in case result of
           JS.Call _ [] -> pure ()
           other -> assertFailure ("Expected JS.Call with no args, got: " ++ show other)

  , testCase "one arg produces JS.Call func [arg] (curried)" $
      let result = Call.generateNormalCall refX [refY]
      in case result of
           JS.Call _ [_] -> pure ()
           other -> assertFailure ("Expected JS.Call with one arg, got: " ++ show other)

  , testCase "two args produces JS.Call A2-helper with func+args" $
      let result = Call.generateNormalCall refX [litInt, litStr]
      in case result of
           JS.Call _ [_, _, _] -> pure ()
           other -> assertFailure ("Expected JS.Call A2 with 3 args (helper+func+args), got: " ++ show other)

  , testCase "three args produces JS.Call A3-helper with func+args" $
      let result = Call.generateNormalCall refX [litInt, litStr, litFloat]
      in case result of
           JS.Call _ [_, _, _, _] -> pure ()
           other -> assertFailure ("Expected JS.Call A3 with 4 args, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- generateTupleCall
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.generateTupleCall'.
generateTupleCallTests :: TestTree
generateTupleCallTests = testGroup "generateTupleCall"
  [ testCase "Tuple.first with one arg produces JS.Access" $
      let result = Call.generateTupleCall basicsHome (Name.fromChars "first") [refX]
      in case result of
           JS.Access _ _ -> pure ()
           other -> assertFailure ("Expected JS.Access for first, got: " ++ show other)

  , testCase "Tuple.second with one arg produces JS.Access" $
      let result = Call.generateTupleCall basicsHome (Name.fromChars "second") [refX]
      in case result of
           JS.Access _ _ -> pure ()
           other -> assertFailure ("Expected JS.Access for second, got: " ++ show other)

  , testCase "Tuple.pair falls back to generateGlobalCall (JS.Call)" $
      let result = Call.generateTupleCall basicsHome (Name.fromChars "pair") [refX, refY]
      in case result of
           JS.Call _ _ -> pure ()
           other -> assertFailure ("Expected JS.Call fallback for pair, got: " ++ show other)

  , testCase "Tuple.first with two args falls back to generateGlobalCall" $
      let result = Call.generateTupleCall basicsHome (Name.fromChars "first") [refX, refY]
      in case result of
           JS.Call _ _ -> pure ()
           other -> assertFailure ("Expected JS.Call fallback for wrong arity, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- generateJsArrayCall
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.generateJsArrayCall'.
generateJsArrayCallTests :: TestTree
generateJsArrayCallTests = testGroup "generateJsArrayCall"
  [ testCase "JsArray.singleton with one arg produces JS.Array" $
      let result = Call.generateJsArrayCall basicsHome (Name.fromChars "singleton") [refX]
      in case result of
           JS.Array _ -> pure ()
           other -> assertFailure ("Expected JS.Array for singleton, got: " ++ show other)

  , testCase "JsArray.singleton wraps arg in single-element array" $
      let result = Call.generateJsArrayCall basicsHome (Name.fromChars "singleton") [refX]
      in case result of
           JS.Array [_] -> pure ()
           other -> assertFailure ("Expected JS.Array [x], got: " ++ show other)

  , testCase "JsArray.unsafeGet with two args produces JS.Index" $
      let result = Call.generateJsArrayCall basicsHome (Name.fromChars "unsafeGet") [litInt, refX]
      in case result of
           JS.Index _ _ -> pure ()
           other -> assertFailure ("Expected JS.Index for unsafeGet, got: " ++ show other)

  , testCase "JsArray.unknown falls back to JS.Call" $
      let result = Call.generateJsArrayCall basicsHome (Name.fromChars "initialize") [litInt, refX]
      in case result of
           JS.Call _ _ -> pure ()
           other -> assertFailure ("Expected JS.Call fallback, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- generateBitwiseCall
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.generateBitwiseCall'.
generateBitwiseCallTests :: TestTree
generateBitwiseCallTests = testGroup "generateBitwiseCall"
  [ testCase "complement with one arg produces JS.Prefix PrefixComplement" $
      let result = Call.generateBitwiseCall basicsHome (Name.fromChars "complement") [refX]
      in case result of
           JS.Prefix JS.PrefixComplement _ -> pure ()
           other -> assertFailure ("Expected PrefixComplement, got: " ++ show other)

  , testCase "and with two args produces JS.Infix OpBitwiseAnd" $
      let result = Call.generateBitwiseCall basicsHome (Name.fromChars "and") [refX, refY]
      in case result of
           JS.Infix JS.OpBitwiseAnd _ _ -> pure ()
           other -> assertFailure ("Expected OpBitwiseAnd, got: " ++ show other)

  , testCase "or with two args produces JS.Infix OpBitwiseOr" $
      let result = Call.generateBitwiseCall basicsHome (Name.fromChars "or") [refX, refY]
      in case result of
           JS.Infix JS.OpBitwiseOr _ _ -> pure ()
           other -> assertFailure ("Expected OpBitwiseOr, got: " ++ show other)

  , testCase "xor with two args produces JS.Infix OpBitwiseXor" $
      let result = Call.generateBitwiseCall basicsHome (Name.fromChars "xor") [refX, refY]
      in case result of
           JS.Infix JS.OpBitwiseXor _ _ -> pure ()
           other -> assertFailure ("Expected OpBitwiseXor, got: " ++ show other)

  , testCase "shiftLeftBy with two args produces JS.Infix OpLShift" $
      let result = Call.generateBitwiseCall basicsHome (Name.fromChars "shiftLeftBy") [refX, refY]
      in case result of
           JS.Infix JS.OpLShift _ _ -> pure ()
           other -> assertFailure ("Expected OpLShift, got: " ++ show other)

  , testCase "shiftRightBy with two args produces JS.Infix OpSpRShift" $
      let result = Call.generateBitwiseCall basicsHome (Name.fromChars "shiftRightBy") [refX, refY]
      in case result of
           JS.Infix JS.OpSpRShift _ _ -> pure ()
           other -> assertFailure ("Expected OpSpRShift, got: " ++ show other)

  , testCase "shiftRightZfBy with two args produces JS.Infix OpZfRShift" $
      let result = Call.generateBitwiseCall basicsHome (Name.fromChars "shiftRightZfBy") [refX, refY]
      in case result of
           JS.Infix JS.OpZfRShift _ _ -> pure ()
           other -> assertFailure ("Expected OpZfRShift, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- jsAppend
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.jsAppend'.
--
-- jsAppend always produces a JS.Call to utils.ap regardless of argument types.
jsAppendTests :: TestTree
jsAppendTests = testGroup "jsAppend"
  [ testCase "jsAppend of two refs produces JS.Call" $
      let result = Call.jsAppend refX refY
      in case result of
           JS.Call _ [_, _] -> pure ()
           other -> assertFailure ("Expected JS.Call [a,b], got: " ++ show other)

  , testCase "jsAppend of two literals produces JS.Call" $
      let result = Call.jsAppend litStr litStr
      in case result of
           JS.Call _ [_, _] -> pure ()
           other -> assertFailure ("Expected JS.Call [a,b], got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- cmp
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.cmp'.
--
-- cmp delegates to a native infix operator when either side is a literal,
-- otherwise wraps a utils.cmp call with a threshold comparison.
cmpTests :: TestTree
cmpTests = testGroup "cmp"
  [ testCase "cmp with literal left uses ideal infix op" $
      let result = Call.cmp JS.OpLt JS.OpLt 0 litInt refY
      in case result of
           JS.Infix JS.OpLt _ _ -> pure ()
           other -> assertFailure ("Expected OpLt infix for literal left, got: " ++ show other)

  , testCase "cmp with literal right uses ideal infix op" $
      let result = Call.cmp JS.OpGt JS.OpGt 0 refX litFloat
      in case result of
           JS.Infix JS.OpGt _ _ -> pure ()
           other -> assertFailure ("Expected OpGt infix for literal right, got: " ++ show other)

  , testCase "cmp with two Refs wraps utils.cmp call" $
      let result = Call.cmp JS.OpLt JS.OpLt 0 refX refY
      in case result of
           JS.Infix _ (JS.Call _ [_, _]) _ -> pure ()
           other -> assertFailure ("Expected cmp(x,y) infix form, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- callHelpers
-- ---------------------------------------------------------------------------

-- | Tests for the 'Call.callHelpers' pre-built A2..A9 map.
callHelpersTests :: TestTree
callHelpersTests = testGroup "callHelpers"
  [ testCase "callHelpers contains entries for 2..9" $
      let expected = 8
      in length [2 :: Int .. 9] @?= expected

  , testCase "generateNormalCall with 4 args uses A4 helper (4+1 = 5 args to Call)" $
      let result = Call.generateNormalCall refX [litInt, litStr, litFloat, litBoolTrue]
      in case result of
           JS.Call _ args -> length args @?= 5
           other -> assertFailure ("Expected JS.Call with 5 args, got: " ++ show other)

  , testCase "generateNormalCall with 9 args uses A9 helper (9+1 = 10 args to Call)" $
      let nineArgs = replicate 9 litInt
          result = Call.generateNormalCall refX nineArgs
      in case result of
           JS.Call _ args -> length args @?= 10
           other -> assertFailure ("Expected JS.Call with 10 args, got: " ++ show other)

  , testCase "generateNormalCall with 10 args falls back to curried calls" $
      let tenArgs = replicate 10 litInt
          result = Call.generateNormalCall refX tenArgs
      in case result of
           JS.Call (JS.Call _ _) [_] -> pure ()
           other -> assertFailure ("Expected nested curried Call for 10 args, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- generateGlobalCall
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.generateGlobalCall'.
generateGlobalCallTests :: TestTree
generateGlobalCallTests = testGroup "generateGlobalCall"
  [ testCase "generateGlobalCall with no args produces JS.Call func []" $
      let result = Call.generateGlobalCall basicsHome (Name.fromChars "negate") []
      in case result of
           JS.Call _ [] -> pure ()
           other -> assertFailure ("Expected JS.Call [] for 0 args, got: " ++ show other)

  , testCase "generateGlobalCall with one arg produces single-arg call" $
      let result = Call.generateGlobalCall basicsHome (Name.fromChars "negate") [refX]
      in case result of
           JS.Call _ [_] -> pure ()
           other -> assertFailure ("Expected JS.Call [x] for 1 arg, got: " ++ show other)

  , testCase "generateGlobalCall with two args uses A2 helper" $
      let result = Call.generateGlobalCall basicsHome (Name.fromChars "add") [refX, refY]
      in case result of
           JS.Call _ [_, _, _] -> pure ()
           other -> assertFailure ("Expected JS.Call A2 with 3 args, got: " ++ show other)
  ]

-- ---------------------------------------------------------------------------
-- toSeqs (pure rendering via append)
-- ---------------------------------------------------------------------------

-- | Tests for 'Call.toSeqs' via the rendered output it produces.
--
-- toSeqs is not directly testable without a Mode, so we verify the
-- flattening via the append-call rendering path using renderExpr.
toSeqsTests :: TestTree
toSeqsTests = testGroup "toSeqs / append rendering"
  [ testCase "isStringLiteral detects only JS.String" $
      let strs = [JS.String "x", JS.Int 0, JS.Float "1.0", JS.Bool True, JS.Null, refX]
          results = fmap Call.isStringLiteral strs
      in results @?= [True, False, False, False, False, False]
  ]
