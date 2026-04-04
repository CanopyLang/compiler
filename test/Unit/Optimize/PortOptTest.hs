{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Optimize.Port.
--
-- Verifies that 'toEncoder', 'toDecoder', and 'toFlagsDecoder' generate
-- the correct optimized expressions for standard Canopy port types.
-- The module is tested by running the 'Names.Tracker' monad with 'Names.run'
-- and inspecting the resulting 'Opt.Expr' via its 'Show' instance (since
-- 'Opt.Expr' has no 'Eq' instance).
--
-- == Test Coverage
--
-- * toEncoder for TUnit: produces Function wrapping null encoder
-- * toEncoder for basic types (Int, Float, Bool, String): references Json.Encode
-- * toEncoder for List: calls list encoder
-- * toEncoder for Maybe: calls destruct encoder
-- * toDecoder for TUnit: produces decodeTuple0 (null decoder returning Unit)
-- * toDecoder for basic types (Int, Float, Bool, String, Value): references Json.Decode
-- * toDecoder for List: calls list decoder
-- * toDecoder for Maybe: calls oneOf decoder
-- * toFlagsDecoder for TUnit: wraps in succeed Unit
-- * toFlagsDecoder for non-unit: delegates to toDecoder
-- * Dependencies tracked: encoder/decoder registrations produce global deps
--
-- @since 0.20.0
module Unit.Optimize.PortOptTest
  ( tests,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Set as Set
import qualified Optimize.Names as Names
import qualified Optimize.Port as Port
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

-- | Main test suite for Optimize.Port.
tests :: TestTree
tests =
  Test.testGroup
    "Optimize.Port"
    [ toEncoderTests,
      toDecoderTests,
      toFlagsDecoderTests,
      dependencyTrackingTests
    ]

-- HELPERS

-- | Run a tracker and return the generated expression.
runExpr :: Names.Tracker Opt.Expr -> Opt.Expr
runExpr tracker =
  let (_, _, expr) = Names.run tracker
   in expr

-- | Run a tracker and return the dependency set.
runDeps :: Names.Tracker Opt.Expr -> Set.Set Opt.Global
runDeps tracker =
  let (deps, _, _) = Names.run tracker
   in deps

-- | Build a primitive TType reference (e.g. Int, Float, Bool, String).
primType :: Name.Name -> Can.Type
primType name = Can.TType ModuleName.basics name []

-- | Build a parameterised TType reference (e.g. List Int).
paramType :: Name.Name -> Can.Type -> Can.Type
paramType name arg = Can.TType ModuleName.basics name [arg]

-- | Assert two Opt.Expr values are equal by comparing their Show output.
assertExprEq :: Opt.Expr -> Opt.Expr -> Test.Assertion
assertExprEq expected actual =
  Test.assertEqual "expression equality" (show expected) (show actual)

-- TO ENCODER TESTS

-- | Tests for 'Port.toEncoder'.
toEncoderTests :: TestTree
toEncoderTests =
  Test.testGroup
    "toEncoder"
    [ Test.testCase "TUnit encoder is a Function wrapping null call" $
        let expr = runExpr (Port.toEncoder Can.TUnit)
         in case expr of
              Opt.Function [_] _ -> pure ()
              other -> Test.assertFailure ("Expected Function, got: " ++ show other),
      Test.testCase "Int encoder expression is a VarGlobal" $
        let expr = runExpr (Port.toEncoder (primType Name.int))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for Int encoder, got: " ++ show other),
      Test.testCase "Float encoder expression is a VarGlobal" $
        let expr = runExpr (Port.toEncoder (primType Name.float))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for Float encoder, got: " ++ show other),
      Test.testCase "Bool encoder expression is a VarGlobal" $
        let expr = runExpr (Port.toEncoder (primType Name.bool))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for Bool encoder, got: " ++ show other),
      Test.testCase "String encoder expression is a VarGlobal" $
        let expr = runExpr (Port.toEncoder (primType Name.string))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for String encoder, got: " ++ show other),
      Test.testCase "List encoder is a Call expression" $
        let expr = runExpr (Port.toEncoder (paramType Name.list (primType Name.int)))
         in case expr of
              Opt.Call _ [_] -> pure ()
              other -> Test.assertFailure ("Expected Call for List encoder, got: " ++ show other),
      Test.testCase "Maybe encoder is a Function wrapping a destruct Call" $
        let expr = runExpr (Port.toEncoder (paramType Name.maybe (primType Name.int)))
         in case expr of
              Opt.Function [_] (Opt.Call _ _) -> pure ()
              other -> Test.assertFailure ("Expected Function(Call) for Maybe encoder, got: " ++ show other),
      Test.testCase "Value encoder is identity (VarGlobal Basics.identity)" $
        let expr = runExpr (Port.toEncoder (primType Name.value))
         in case expr of
              Opt.VarGlobal (Opt.Global home name) ->
                Test.assertEqual "identity global home" ModuleName.basics home >>
                Test.assertEqual "identity name" (show Name.identity) (show name)
              other -> Test.assertFailure ("Expected VarGlobal identity for Value encoder, got: " ++ show other)
    ]

-- TO DECODER TESTS

-- | Tests for 'Port.toDecoder'.
toDecoderTests :: TestTree
toDecoderTests =
  Test.testGroup
    "toDecoder"
    [ Test.testCase "TUnit decoder is a Call (null [Unit])" $
        let expr = runExpr (Port.toDecoder Can.TUnit)
         in case expr of
              Opt.Call _ [Opt.Unit] -> pure ()
              other -> Test.assertFailure ("Expected Call(Unit) for TUnit decoder, got: " ++ show other),
      Test.testCase "Int decoder is a VarGlobal" $
        let expr = runExpr (Port.toDecoder (primType Name.int))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for Int decoder, got: " ++ show other),
      Test.testCase "Float decoder is a VarGlobal" $
        let expr = runExpr (Port.toDecoder (primType Name.float))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for Float decoder, got: " ++ show other),
      Test.testCase "Bool decoder is a VarGlobal" $
        let expr = runExpr (Port.toDecoder (primType Name.bool))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for Bool decoder, got: " ++ show other),
      Test.testCase "String decoder is a VarGlobal" $
        let expr = runExpr (Port.toDecoder (primType Name.string))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for String decoder, got: " ++ show other),
      Test.testCase "Value decoder is a VarGlobal" $
        let expr = runExpr (Port.toDecoder (primType Name.value))
         in case expr of
              Opt.VarGlobal _ -> pure ()
              other -> Test.assertFailure ("Expected VarGlobal for Value decoder, got: " ++ show other),
      Test.testCase "List decoder is a Call" $
        let expr = runExpr (Port.toDecoder (paramType Name.list (primType Name.int)))
         in case expr of
              Opt.Call _ [_] -> pure ()
              other -> Test.assertFailure ("Expected Call for List decoder, got: " ++ show other),
      Test.testCase "Maybe decoder is a Call wrapping oneOf" $
        let expr = runExpr (Port.toDecoder (paramType Name.maybe (primType Name.int)))
         in case expr of
              Opt.Call _ [Opt.List _] -> pure ()
              other -> Test.assertFailure ("Expected Call(List) for Maybe decoder, got: " ++ show other)
    ]

-- TO FLAGS DECODER TESTS

-- | Tests for 'Port.toFlagsDecoder'.
toFlagsDecoderTests :: TestTree
toFlagsDecoderTests =
  Test.testGroup
    "toFlagsDecoder"
    [ Test.testCase "TUnit flags decoder is Call succeed Unit" $
        let expr = runExpr (Port.toFlagsDecoder Can.TUnit)
         in case expr of
              Opt.Call _ [Opt.Unit] -> pure ()
              other -> Test.assertFailure ("Expected Call(Unit) for TUnit flags decoder, got: " ++ show other),
      Test.testCase "Int flags decoder delegates to toDecoder" $
        let flagsExpr = runExpr (Port.toFlagsDecoder (primType Name.int))
            decoderExpr = runExpr (Port.toDecoder (primType Name.int))
         in show flagsExpr @?= show decoderExpr,
      Test.testCase "Bool flags decoder delegates to toDecoder" $
        let flagsExpr = runExpr (Port.toFlagsDecoder (primType Name.bool))
            decoderExpr = runExpr (Port.toDecoder (primType Name.bool))
         in show flagsExpr @?= show decoderExpr
    ]

-- DEPENDENCY TRACKING TESTS

-- | Tests that encoder and decoder registrations track global dependencies.
dependencyTrackingTests :: TestTree
dependencyTrackingTests =
  Test.testGroup
    "dependency tracking"
    [ Test.testCase "Int encoder registers at least one global dep" $
        Set.null (runDeps (Port.toEncoder (primType Name.int))) @?= False,
      Test.testCase "Int decoder registers at least one global dep" $
        Set.null (runDeps (Port.toDecoder (primType Name.int))) @?= False,
      Test.testCase "TUnit encoder registers at least one global dep" $
        Set.null (runDeps (Port.toEncoder Can.TUnit)) @?= False,
      Test.testCase "TUnit decoder registers at least one global dep" $
        Set.null (runDeps (Port.toDecoder Can.TUnit)) @?= False,
      Test.testCase "List Int encoder registers more deps than Int encoder alone" $
        let listDeps = runDeps (Port.toEncoder (paramType Name.list (primType Name.int)))
            intDeps = runDeps (Port.toEncoder (primType Name.int))
         in Set.size listDeps >= Set.size intDeps @?= True
    ]
