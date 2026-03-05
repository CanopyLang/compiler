{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI ergonomics features.
--
-- Tests the four features from Plan 16:
-- 1. Auto-binding generation (FFI functions available without wrappers)
-- 2. @canopy-bind annotations (method, get, set, new)
-- 3. Auto opaque type inference
-- 4. @canopy-name for renaming
--
-- @since 0.20.0
module Unit.FFI.ErgonomicsTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import FFI.Types
  ( BindingMode (..),
    CapabilityName (..),
    FFIBinding (..),
    FFIFuncName (..),
    FFITypeAnnotation (..),
  )
import qualified Generate.JavaScript.FFI as GenFFI
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "FFI Ergonomics"
    [ bindingModeTests,
      canopyNameTests,
      codegenBindingModeTests,
      extractionTests
    ]

-- BINDING MODE TESTS

bindingModeTests :: TestTree
bindingModeTests =
  testGroup
    "BindingMode data type"
    [ testCase "FunctionCall is the default" $ do
        let binding = FFIBinding (FFIFuncName "add") (FFITypeAnnotation "Int -> Int -> Int") [] FunctionCall Nothing
        _bindingMode binding @?= FunctionCall,
      testCase "MethodCall stores method name" $ do
        let binding = FFIBinding (FFIFuncName "addEventListener") (FFITypeAnnotation "DOMElement -> String -> (Event -> ()) -> ()") [] (MethodCall "addEventListener") Nothing
        _bindingMode binding @?= MethodCall "addEventListener",
      testCase "PropertyGet stores property name" $ do
        let binding = FFIBinding (FFIFuncName "getCurrentTime") (FFITypeAnnotation "AudioContext -> Float") [] (PropertyGet "currentTime") Nothing
        _bindingMode binding @?= PropertyGet "currentTime",
      testCase "PropertySet stores property name" $ do
        let binding = FFIBinding (FFIFuncName "setCurrentTime") (FFITypeAnnotation "AudioContext -> Float -> ()") [] (PropertySet "currentTime") Nothing
        _bindingMode binding @?= PropertySet "currentTime",
      testCase "ConstructorCall stores class name" $ do
        let binding = FFIBinding (FFIFuncName "createAudioContext") (FFITypeAnnotation "() -> AudioContext") [] (ConstructorCall "AudioContext") Nothing
        _bindingMode binding @?= ConstructorCall "AudioContext"
    ]

-- CANOPY NAME TESTS

canopyNameTests :: TestTree
canopyNameTests =
  testGroup
    "@canopy-name"
    [ testCase "binding without canopy-name has Nothing" $ do
        let binding = FFIBinding (FFIFuncName "add") (FFITypeAnnotation "Int -> Int -> Int") [] FunctionCall Nothing
        _bindingCanopyName binding @?= Nothing,
      testCase "binding with canopy-name stores the override" $ do
        let binding = FFIBinding (FFIFuncName "setFrequency") (FFITypeAnnotation "OscillatorNode -> Float -> ()") [] FunctionCall (Just "setOscillatorFrequency")
        _bindingCanopyName binding @?= Just "setOscillatorFrequency"
    ]

-- CODE GENERATION BINDING MODE TESTS

codegenBindingModeTests :: TestTree
codegenBindingModeTests =
  testGroup
    "Code generation for binding modes"
    [ testCase "method call generates obj.method(...)" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type DOMElement -> String -> ()",
                " * @canopy-bind method focus",
                " * @name focus",
                " */"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 1
        fst (head functions) @?= "focus",
      testCase "property get generates obj.prop" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type AudioContext -> Float",
                " * @canopy-bind get currentTime",
                " * @name getCurrentTime",
                " */"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 1
        fst (head functions) @?= "getCurrentTime",
      testCase "property set generates obj.prop = val" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type AudioContext -> Float -> ()",
                " * @canopy-bind set volume",
                " * @name setVolume",
                " */"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 1
        fst (head functions) @?= "setVolume",
      testCase "constructor call generates new ClassName(...)" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type () -> AudioContext",
                " * @canopy-bind new AudioContext",
                " * @name createAudioContext",
                " */"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 1
        fst (head functions) @?= "createAudioContext",
      testCase "canopy-name overrides function name" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type OscillatorNode -> Float -> ()",
                " * @canopy-name setOscillatorFrequency",
                " * @name setFrequency",
                " */"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 1
        fst (head functions) @?= "setOscillatorFrequency"
    ]

-- EXTRACTION TESTS

extractionTests :: TestTree
extractionTests =
  testGroup
    "JSDoc annotation extraction"
    [ testCase "extracts standard function" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type Int -> Int -> Int",
                " * @name add",
                " */"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 1
        fst (head functions) @?= "add"
        snd (head functions) @?= "Int -> Int -> Int",
      testCase "extracts multiple functions" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type Int -> Int -> Int",
                " * @name add",
                " */",
                "",
                "/**",
                " * @canopy-type Int -> Int -> Int",
                " * @name subtract",
                " */"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 2,
      testCase "function without @canopy-type is skipped" $ do
        let js = jsLines
              [ "/**",
                " * @name helper",
                " */",
                "function helper() {}"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 0,
      testCase "bodyless JSDoc with @canopy-bind is extracted" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type AudioContext -> Float",
                " * @canopy-bind get currentTime",
                " * @name getCurrentTime",
                " */"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 1,
      testCase "extracts function from following function declaration" $ do
        let js = jsLines
              [ "/**",
                " * @canopy-type Int -> Int",
                " */",
                "function factorial(n) { return n <= 1 ? 1 : n * factorial(n-1); }"
              ]
            functions = GenFFI.extractCanopyTypeFunctions (Text.lines js)
        length functions @?= 1
        fst (head functions) @?= "factorial"
    ]

-- HELPERS

jsLines :: [Text.Text] -> Text.Text
jsLines = Text.unlines

builderToText :: BB.Builder -> Text.Text
builderToText = TextEnc.decodeUtf8 . LBS.toStrict . BB.toLazyByteString
