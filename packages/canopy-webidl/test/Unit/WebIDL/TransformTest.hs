{-# LANGUAGE OverloadedStrings #-}

-- | Transform Tests
--
-- Tests for WebIDL type transformation functionality.
--
-- @since 0.20.0
module Unit.WebIDL.TransformTest (tests) where

import Data.Text (Text)
import Test.Tasty
import Test.Tasty.HUnit

import WebIDL.AST
import WebIDL.Config
import WebIDL.Transform


tests :: TestTree
tests = testGroup "WebIDL.Transform"
  [ typeTransformTests
  , nameConversionTests
  , mixinResolutionTests
  , partialMergeTests
  ]


typeTransformTests :: TestTree
typeTransformTests = testGroup "Type transformation"
  [ testCase "primitive boolean transforms to CTBool" $ do
      let result = transformType defaultConfig (TyPrimitive PrimBoolean)
      result @?= CTBool

  , testCase "primitive integer types transform to CTInt" $ do
      transformType defaultConfig (TyPrimitive PrimByte) @?= CTInt
      transformType defaultConfig (TyPrimitive PrimShort) @?= CTInt
      transformType defaultConfig (TyPrimitive PrimLong) @?= CTInt
      transformType defaultConfig (TyPrimitive PrimUnsignedLong) @?= CTInt

  , testCase "primitive float types transform to CTFloat" $ do
      transformType defaultConfig (TyPrimitive PrimFloat) @?= CTFloat
      transformType defaultConfig (TyPrimitive PrimDouble) @?= CTFloat

  , testCase "string types transform to CTString" $ do
      transformType defaultConfig (TyString StrDOMString) @?= CTString
      transformType defaultConfig (TyString StrUSVString) @?= CTString
      transformType defaultConfig (TyString StrByteString) @?= CTString

  , testCase "nullable transforms to CTMaybe" $ do
      let result = transformType defaultConfig (TyNullable (TyString StrDOMString))
      result @?= CTMaybe CTString

  , testCase "sequence transforms to CTList" $ do
      let result = transformType defaultConfig (TySequence (TyIdentifier "Element"))
      result @?= CTList (CTCustom "Element")

  , testCase "Promise transforms to CTTask" $ do
      let result = transformType defaultConfig (TyPromise (TyIdentifier "Response"))
      result @?= CTTask (CTCustom "Error") (CTCustom "Response")

  , testCase "record transforms to CTDict" $ do
      let result = transformType defaultConfig (TyRecord StrDOMString TyAny)
      result @?= CTDict CTString CTValue

  , testCase "void transforms to CTUnit" $ do
      transformType defaultConfig TyVoid @?= CTUnit
      transformType defaultConfig TyUndefined @?= CTUnit

  , testCase "any transforms to CTValue" $ do
      transformType defaultConfig TyAny @?= CTValue
      transformType defaultConfig TyObject @?= CTValue

  , testCase "identifier transforms to CTCustom" $ do
      let result = transformType defaultConfig (TyIdentifier "HTMLElement")
      result @?= CTCustom "HTMLElement"

  , testCase "nested types transform correctly" $ do
      let input = TyNullable (TySequence (TyIdentifier "Node"))
      let expected = CTMaybe (CTList (CTCustom "Node"))
      transformType defaultConfig input @?= expected

  , testCase "buffer types transform to Bytes" $ do
      transformType defaultConfig (TyBuffer BufArrayBuffer) @?= CTCustom "Bytes"
      transformType defaultConfig (TyBuffer BufUint8Array) @?= CTCustom "Bytes"
  ]


nameConversionTests :: TestTree
nameConversionTests = testGroup "Name conversion"
  [ testCase "toModuleName adds prefix" $ do
      let result = toModuleName defaultConfig "Element"
      result @?= "WebAPI.Element"

  , testCase "toTypeName converts to PascalCase" $ do
      toTypeName "loading" @?= "Loading"
      toTypeName "interactive" @?= "Interactive"

  , testCase "toFunctionName converts to camelCase" $ do
      toFunctionName "getElementById" @?= "getElementById"
      toFunctionName "GetElementById" @?= "getElementById"

  , testCase "toFieldName converts to camelCase" $ do
      toFieldName "bubbles" @?= "bubbles"
      toFieldName "Bubbles" @?= "bubbles"
  ]


mixinResolutionTests :: TestTree
mixinResolutionTests = testGroup "Mixin resolution"
  [ testCase "resolveMixins merges mixin members" $ do
      let mixin = DefMixin (Mixin [] "TestMixin"
            [ MMOperation (Operation [] Nothing TyVoid (Just "mixinMethod") [])
            ])
      let interface = DefInterface (Interface [] "TestInterface" Nothing
            [ IMOperation (Operation [] Nothing TyVoid (Just "ownMethod") [])
            ])
      let includes = DefIncludes "TestInterface" "TestMixin"
      let defs = [mixin, interface, includes]
      let resolved = resolveMixins defs

      case head (filter isInterface resolved) of
        DefInterface intf -> do
          length (intfMembers intf) @?= 2
        _ -> assertFailure "Expected interface"

  , testCase "mixin not applied to wrong interface" $ do
      let mixin = DefMixin (Mixin [] "MixinA" [])
      let interface = DefInterface (Interface [] "InterfaceB" Nothing [])
      let includes = DefIncludes "InterfaceC" "MixinA"  -- Different target
      let defs = [mixin, interface, includes]
      let resolved = resolveMixins defs

      case head (filter isInterface resolved) of
        DefInterface intf ->
          length (intfMembers intf) @?= 0
        _ -> assertFailure "Expected interface"
  ]


partialMergeTests :: TestTree
partialMergeTests = testGroup "Partial interface merging"
  [ testCase "mergePartials combines interface members" $ do
      let main = DefInterface (Interface [] "Element" Nothing
            [ IMAttribute (Attribute [] False False (TyString StrDOMString) "id")
            ])
      let partial = DefPartialInterface (PartialInterface [] "Element"
            [ IMAttribute (Attribute [] False False (TyString StrDOMString) "className")
            ])
      let defs = [main, partial]
      let merged = mergePartials defs

      case head (filter isInterface merged) of
        DefInterface intf -> do
          intfName intf @?= "Element"
          length (intfMembers intf) @?= 2
        _ -> assertFailure "Expected interface"

  , testCase "mergePartials combines dictionary members" $ do
      let main = DefDictionary (Dictionary [] "Options" Nothing
            [ DictionaryMember [] False (TyPrimitive PrimBoolean) "enabled" Nothing
            ])
      let partial = DefPartialDictionary (Dictionary [] "Options" Nothing
            [ DictionaryMember [] False (TyPrimitive PrimBoolean) "verbose" Nothing
            ])
      let defs = [main, partial]
      let merged = mergePartials defs

      case head (filter isDictionary merged) of
        DefDictionary dict -> do
          dictName dict @?= "Options"
          length (dictMembers dict) @?= 2
        _ -> assertFailure "Expected dictionary"
  ]


-- Helper predicates

isInterface :: Definition -> Bool
isInterface (DefInterface _) = True
isInterface _ = False

isDictionary :: Definition -> Bool
isDictionary (DefDictionary _) = True
isDictionary _ = False
