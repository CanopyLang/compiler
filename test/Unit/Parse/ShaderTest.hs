{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit.Parse.ShaderTest — Tests for the @[glsl|...|]@ shader literal parser.
--
-- Exercises 'Parse.Shader.shader' through the full expression parser
-- ('Parse.Expression.expression').  Each test verifies that well-formed GLSL
-- blocks produce 'Src.Shader' nodes and that malformed inputs are rejected
-- with syntax errors.
--
-- The GLSL parser is provided by the @language-glsl@ library and is invoked
-- internally by 'Parse.Shader.parseGlsl'.  Tests therefore cover both the
-- Canopy bracket syntax and the downstream GLSL parsing step.
--
-- @since 0.19.1
module Unit.Parse.ShaderTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Parse.Expression as Expr
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase)

-- ---------------------------------------------------------------------------
-- Test harness
-- ---------------------------------------------------------------------------

-- | Parse a Canopy expression from a raw Haskell 'String'.
parseExpr :: String -> Either SyntaxError.Expr Src.Expr
parseExpr s = fst <$> Parse.fromByteString Expr.expression SyntaxError.Start (C8.pack s)

-- ---------------------------------------------------------------------------
-- Top-level test tree
-- ---------------------------------------------------------------------------

-- | All shader literal parsing tests.
tests :: TestTree
tests =
  testGroup
    "Parse.Shader"
    [ testWellFormed,
      testMalformed
    ]

-- ---------------------------------------------------------------------------
-- Well-formed shader literals
-- ---------------------------------------------------------------------------

-- | Tests for syntactically and semantically valid @[glsl|...|]@ blocks.
testWellFormed :: TestTree
testWellFormed =
  testGroup
    "well-formed shaders"
    [ testCase "minimal empty main" $ case parseExpr "[glsl|void main() {}|]" of
        Right (Ann.At _ (Src.Shader _ _)) -> return ()
        other -> assertFailure ("expected Shader, got: " <> show other),
      testCase "shader with uniform float" $
        let src = "[glsl|uniform float time;void main(){}|]"
        in case parseExpr src of
          Right (Ann.At _ (Src.Shader _ _)) -> return ()
          other -> assertFailure ("expected Shader, got: " <> show other),
      testCase "shader with attribute vec2" $
        let src = "[glsl|attribute vec2 pos;void main(){}|]"
        in case parseExpr src of
          Right (Ann.At _ (Src.Shader _ _)) -> return ()
          other -> assertFailure ("expected Shader, got: " <> show other),
      testCase "shader with varying vec4" $
        let src = "[glsl|varying vec4 color;void main(){}|]"
        in case parseExpr src of
          Right (Ann.At _ (Src.Shader _ _)) -> return ()
          other -> assertFailure ("expected Shader, got: " <> show other),
      testCase "shader with multiple declarations" $
        let src = "[glsl|uniform float t;attribute vec3 v;void main(){}|]"
        in case parseExpr src of
          Right (Ann.At _ (Src.Shader _ _)) -> return ()
          other -> assertFailure ("expected Shader, got: " <> show other),
      testCase "multiline shader body" $
        let src = "[glsl|\nvoid main() {\n  gl_Position = vec4(0.0);\n}\n|]"
        in case parseExpr src of
          Right (Ann.At _ (Src.Shader _ _)) -> return ()
          other -> assertFailure ("expected Shader, got: " <> show other)
    ]

-- ---------------------------------------------------------------------------
-- Malformed shader literals
-- ---------------------------------------------------------------------------

-- | Tests for shader inputs that the parser must reject.
testMalformed :: TestTree
testMalformed =
  testGroup
    "malformed shaders"
    [ testCase "unterminated shader block fails" $ case parseExpr "[glsl|void main() {}" of
        Left _ -> return ()
        Right _ -> assertFailure "expected parse error for unterminated shader",
      testCase "incomplete bracket [gls| fails" $ case parseExpr "[gls|void main(){}|]" of
        Left _ -> return ()
        Right _ -> assertFailure "expected parse error for bad opening bracket",
      testCase "empty brackets [glsl||] parses or fails gracefully" $
        case parseExpr "[glsl||]" of
          Right (Ann.At _ (Src.Shader _ _)) -> return ()
          Left _ -> return ()
          Right other -> assertFailure ("expected Shader or parse error, got: " <> show other)
    ]
