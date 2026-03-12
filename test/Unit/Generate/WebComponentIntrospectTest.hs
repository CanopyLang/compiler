{-# LANGUAGE OverloadedStrings #-}

-- | Tests for Web Component interface introspection.
--
-- Verifies that flag attributes and port events are correctly extracted
-- from module metadata with proper type coercion and name conversion.
--
-- @since 0.20.1
module Unit.Generate.WebComponentIntrospectTest (tests) where

import Generate.JavaScript.WebComponent (AttrCoercion (..), FlagAttr (..), PortEvent (..))
import qualified Generate.JavaScript.WebComponent.Introspect as Introspect
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup "WebComponent.Introspect"
    [ flagAttrTests
    , portEventTests
    , coercionTests
    ]

flagAttrTests :: TestTree
flagAttrTests =
  Test.testGroup "extractFlagAttrs"
    [ HUnit.testCase "empty list produces no attrs" $
        Introspect.extractFlagAttrs [] @?= []
    , HUnit.testCase "Int field maps to CoerceInt" $
        Introspect.extractFlagAttrs [("count", "Int")]
          @?= [FlagAttr "count" "count" CoerceInt]
    , HUnit.testCase "Bool field maps to CoerceBool with kebab attr" $
        Introspect.extractFlagAttrs [("isEnabled", "Bool")]
          @?= [FlagAttr "isEnabled" "is-enabled" CoerceBool]
    , HUnit.testCase "Float field maps to CoerceFloat" $
        Introspect.extractFlagAttrs [("ratio", "Float")]
          @?= [FlagAttr "ratio" "ratio" CoerceFloat]
    , HUnit.testCase "String field maps to CoerceString" $
        Introspect.extractFlagAttrs [("title", "String")]
          @?= [FlagAttr "title" "title" CoerceString]
    , HUnit.testCase "unknown type defaults to CoerceString" $
        Introspect.extractFlagAttrs [("data", "CustomType")]
          @?= [FlagAttr "data" "data" CoerceString]
    , HUnit.testCase "multiple fields preserve order" $
        Introspect.extractFlagAttrs [("count", "Int"), ("title", "String")]
          @?= [ FlagAttr "count" "count" CoerceInt
               , FlagAttr "title" "title" CoerceString
               ]
    , HUnit.testCase "camelCase field becomes kebab-case attr" $
        Introspect.extractFlagAttrs [("initialCount", "Int")]
          @?= [FlagAttr "initialCount" "initial-count" CoerceInt]
    ]

portEventTests :: TestTree
portEventTests =
  Test.testGroup "extractPortEvents"
    [ HUnit.testCase "empty list produces no events" $
        Introspect.extractPortEvents [] @?= []
    , HUnit.testCase "outgoing port becomes event" $
        Introspect.extractPortEvents [("onCountChange", "outgoing")]
          @?= [PortEvent "onCountChange" "on-count-change"]
    , HUnit.testCase "incoming port filtered out" $
        Introspect.extractPortEvents [("setCount", "incoming")] @?= []
    , HUnit.testCase "mixed directions filter correctly" $
        Introspect.extractPortEvents
          [("onResult", "outgoing"), ("setInput", "incoming"), ("onError", "outgoing")]
          @?= [ PortEvent "onResult" "on-result"
               , PortEvent "onError" "on-error"
               ]
    , HUnit.testCase "unknown direction filtered out" $
        Introspect.extractPortEvents [("mystery", "bidirectional")] @?= []
    ]

coercionTests :: TestTree
coercionTests =
  Test.testGroup "canopyTypeToCoercion"
    [ HUnit.testCase "Int maps to CoerceInt" $
        Introspect.canopyTypeToCoercion "Int" @?= CoerceInt
    , HUnit.testCase "Float maps to CoerceFloat" $
        Introspect.canopyTypeToCoercion "Float" @?= CoerceFloat
    , HUnit.testCase "Bool maps to CoerceBool" $
        Introspect.canopyTypeToCoercion "Bool" @?= CoerceBool
    , HUnit.testCase "String maps to CoerceString" $
        Introspect.canopyTypeToCoercion "String" @?= CoerceString
    , HUnit.testCase "Text defaults to CoerceString" $
        Introspect.canopyTypeToCoercion "Text" @?= CoerceString
    , HUnit.testCase "custom type defaults to CoerceString" $
        Introspect.canopyTypeToCoercion "MyCustomType" @?= CoerceString
    , HUnit.testCase "empty string defaults to CoerceString" $
        Introspect.canopyTypeToCoercion "" @?= CoerceString
    ]
