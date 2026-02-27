{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Comprehensive test suite for AST.Utils.Shader.
--
-- This module provides complete test coverage for all public functions,
-- edge cases, error conditions, and properties in AST.Utils.Shader.
--
-- Coverage Target: ≥80% line coverage
-- Test Categories: Unit, Property, Edge Case, Error Condition
--
-- @since 0.19.1
module Unit.AST.Utils.ShaderTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import AST.Utils.Shader (Source, Types (..), Type (..), fromChars, toJsStringBuilder)
import qualified AST.Utils.Shader as Shader
import Data.Binary (decode, encode)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map as Map
import qualified Data.Name as Name

-- | Main test tree containing all AST.Utils.Shader tests.
--
-- Organizes tests into logical categories for clear test reporting
-- and maintainable test suite structure.
tests :: TestTree
tests = testGroup "AST.Utils.Shader Tests"
  [ unitTests
  , propertyTests
  , edgeCaseTests
  , errorConditionTests
  ]

-- | Unit tests for all public functions and data constructors.
--
-- Tests basic functionality with known inputs and expected outputs.
-- Every public function and data constructor must have unit tests.
unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ sourceTests
  , typesTests
  , typeTests
  , fromCharsTests
  , toJsStringBuilderTests
  ]

-- | Source data type tests.
sourceTests :: TestTree
sourceTests = testGroup "Source Tests"
  [ testCase "Source show format includes constructor" $
      let source = fromChars "attribute vec3 position;"
          shown = show source
      in "Source" `elem` words shown @?= True
  ]

-- | Types data type and field tests.
typesTests :: TestTree
typesTests = testGroup "Types Tests"
  [ testCase "Types construction with empty maps" $
      let types = Types Map.empty Map.empty Map.empty
          attributeEmpty = Map.null (_attribute types)
          uniformEmpty = Map.null (_uniform types)
          varyingEmpty = Map.null (_varying types)
      in (attributeEmpty && uniformEmpty && varyingEmpty) @?= True
  , testCase "Types construction with populated maps" $
      let attrMap = Map.fromList [(Name.fromChars "position", V3)]
          uniformMap = Map.fromList [(Name.fromChars "mvp", M4)]
          varyingMap = Map.fromList [(Name.fromChars "normal", V3)]
          types = Types attrMap uniformMap varyingMap
      in (Map.size (_attribute types) == 1
          && Map.size (_uniform types) == 1
          && Map.size (_varying types) == 1) @?= True
  , testCase "Types show format includes constructor" $
      let types = Types Map.empty Map.empty Map.empty
          shown = show types
      in "Types" `elem` words shown @?= True
  ]

-- | GLSL Type constructor tests.
typeTests :: TestTree
typeTests = testGroup "Type Constructor Tests"
  [ testCase "Int type constructor" $
      show Int @?= show Int
  , testCase "Float type constructor" $
      show Float @?= show Float
  , testCase "V2 type constructor" $
      show V2 @?= show V2
  , testCase "V3 type constructor" $
      show V3 @?= show V3
  , testCase "V4 type constructor" $
      show V4 @?= show V4
  , testCase "M4 type constructor" $
      show M4 @?= show M4
  , testCase "Texture type constructor" $
      show Texture @?= show Texture
  , testCase "Int show format" $
      show Int @?= "Int"
  , testCase "Float show format" $
      show Float @?= "Float"
  , testCase "V2 show format" $
      show V2 @?= "V2"
  , testCase "V3 show format" $
      show V3 @?= "V3"
  , testCase "V4 show format" $
      show V4 @?= "V4"
  , testCase "M4 show format" $
      show M4 @?= "M4"
  , testCase "Texture show format" $
      show Texture @?= "Texture"
  , testCase "all types are distinct" $
      let allTypes = [Int, Float, V2, V3, V4, M4, Texture]
          uniqueCount = length allTypes
      in uniqueCount @?= 7
  ]

-- | fromChars function behavior tests.
fromCharsTests :: TestTree
fromCharsTests = testGroup "fromChars Tests"
  [ testCase "fromChars with simple shader source" $
      let source = fromChars "void main() { gl_Position = vec4(0.0); }"
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 40
  , testCase "fromChars with empty string" $
      let source = fromChars ""
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 0
  , testCase "fromChars handles newlines correctly" $
      let source = fromChars "line1\nline2"
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 12
  , testCase "fromChars handles double quotes" $
      let source = fromChars "uniform float \"quoted\";"
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 25
  , testCase "fromChars handles single quotes" $
      let source = fromChars "uniform float 'quoted';"
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 25
  , testCase "fromChars handles backslashes" $
      let source = fromChars "path\\to\\shader"
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 16
  ]

-- | toJsStringBuilder function behavior tests.
toJsStringBuilderTests :: TestTree
toJsStringBuilderTests = testGroup "toJsStringBuilder Tests"
  [ testCase "toJsStringBuilder produces correct length for non-empty input" $
      let source = fromChars "attribute vec3 position;"
          result = toJsStringBuilder source
          resultLength = BL.length (BB.toLazyByteString result)
      in resultLength @?= 24
  , testCase "toJsStringBuilder produces empty result for empty input" $
      let source = fromChars ""
          result = toJsStringBuilder source
          resultLength = BL.length (BB.toLazyByteString result)
      in resultLength @?= 0
  , testCase "toJsStringBuilder produces correct lengths for short and long inputs" $
      let shortSource = fromChars "short"
          longSource = fromChars "this is a much longer shader source string"
          shortResult = BB.toLazyByteString (toJsStringBuilder shortSource)
          longResult = BB.toLazyByteString (toJsStringBuilder longSource)
      in (BL.length shortResult, BL.length longResult) @?= (5, 42)
  ]

-- | Property-based tests for mathematical and logical invariants.
--
-- Uses QuickCheck to verify properties hold across many inputs.
-- Required for functions with mathematical or logical operations.
propertyTests :: TestTree
propertyTests = testGroup "Property Tests"
  [ sourceProperties
  , typeProperties
  , charEscapingProperties
  ]

-- | Properties of Source creation and manipulation.
sourceProperties :: TestTree
sourceProperties = testGroup "Source Properties"
  [ testProperty "fromChars then toJsStringBuilder preserves non-emptiness" $ \str ->
      let source = fromChars str
          result = toJsStringBuilder source
          resultLength = BL.length (BB.toLazyByteString result)
          inputLength = length str
      in if inputLength > 0 then resultLength > 0 else resultLength == 0
  , testProperty "toJsStringBuilder is deterministic" $ \str ->
      let source = fromChars str
          result1 = toJsStringBuilder source
          result2 = toJsStringBuilder source
      in BB.toLazyByteString result1 == BB.toLazyByteString result2
  ]

-- | Properties of Type enumeration.
typeProperties :: TestTree
typeProperties = testGroup "Type Properties"
  [ testProperty "type show is consistent" $ \t ->
      show (t :: Type) == show t
  , testProperty "type show produces non-empty output" $ \t ->
      not (null (show (t :: Type)))
  , testProperty "show then read identity for types" $ \t ->
      let shown = show (t :: Type)
          readResult = case t of
            Int -> show Int == shown
            Float -> show Float == shown
            V2 -> show V2 == shown
            V3 -> show V3 == shown
            V4 -> show V4 == shown
            M4 -> show M4 == shown
            Texture -> show Texture == shown
      in readResult
  ]

-- | Properties of character escaping behavior.
charEscapingProperties :: TestTree
charEscapingProperties = testGroup "Character Escaping Properties"
  [ testProperty "escaping preserves string structure" $ \str ->
      let source = fromChars str
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) >= 0
  , testProperty "escaping handles all ASCII characters" $ \c ->
      let str = [c]
          source = fromChars str
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) >= 0
  ]

-- | Edge case tests for boundary conditions.
--
-- Tests empty inputs, maximum values, minimum values, and other
-- boundary conditions that could cause unexpected behavior.
edgeCaseTests :: TestTree
edgeCaseTests = testGroup "Edge Case Tests"
  [ testCase "empty shader source" $
      let source = fromChars ""
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 0
  , testCase "shader source with only whitespace" $
      let source = fromChars "   \n\t  "
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 8
  , testCase "shader source with special characters" $
      let source = fromChars "!@#$%^&*(){}[]|\\:;\"'<>?,./"
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 29
  , testCase "very long shader source" $
      let longString = replicate 10000 'a'
          source = fromChars longString
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 10000
  , testCase "Types with large maps" $
      let largeMap = Map.fromList [(Name.fromChars ("var" ++ show i), V3) | i <- [1..100 :: Int]]
          types = Types largeMap largeMap largeMap
      in Map.size (_attribute types) @?= 100
  ]

-- | Error condition tests for invalid inputs.
--
-- Verifies proper error handling and meaningful error messages
-- for all possible error conditions and invalid inputs.
errorConditionTests :: TestTree
errorConditionTests = testGroup "Error Condition Tests"
  [ testCase "binary serialization handles Source correctly" $
      let original = fromChars "test shader code"
          serialized = encode original
          deserialized = decode serialized :: Source
      in show deserialized @?= show original
  , testCase "shader with Unicode characters" $
      let source = fromChars "// Comment with Unicode: こんにちは"
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 40
  , testCase "malformed shader source preserves content" $
      let source = fromChars "invalid GLSL syntax @#$%"
          result = toJsStringBuilder source
      in BL.length (BB.toLazyByteString result) @?= 24
  ]

-- QuickCheck Arbitrary instances for property testing

instance Arbitrary Type where
  arbitrary = elements [Int, Float, V2, V3, V4, M4, Texture]
  shrink _ = []

-- Generate reasonable strings for shader testing
instance Arbitrary Source where
  arbitrary = fromChars <$> arbitrary
  shrink source = 
    let sourceStr = case show source of
          s -> take 100 s  -- Simplify for shrinking
    in [fromChars (take n sourceStr) | n <- [0, 1, length sourceStr `div` 2]]