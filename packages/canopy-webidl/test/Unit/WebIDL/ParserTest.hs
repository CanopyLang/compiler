{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Parser Tests
--
-- Tests for WebIDL parser functionality.
--
-- @since 0.20.0
module Unit.WebIDL.ParserTest (tests) where

import Data.Either (isRight)
import Test.Tasty
import Test.Tasty.HUnit

import WebIDL.AST
import WebIDL.Parser


tests :: TestTree
tests = testGroup "WebIDL.Parser"
  [ interfaceTests
  , operationTests
  , attributeTests
  , dictionaryTests
  , enumTests
  , typedefTests
  , typeTests
  , extendedAttributeTests
  ]


interfaceTests :: TestTree
interfaceTests = testGroup "Interface parsing"
  [ testCase "empty interface" $ do
      let input = "interface Element {};"
      let result = parseDefinition input
      isRight result @?= True
      case result of
        Right (DefInterface intf) -> do
          intfName intf @?= "Element"
          intfMembers intf @?= []
          intfInherits intf @?= Nothing
        _ -> assertFailure "Expected DefInterface"

  , testCase "interface with inheritance" $ do
      let input = "interface HTMLElement : Element {};"
      let result = parseDefinition input
      isRight result @?= True
      case result of
        Right (DefInterface intf) -> do
          intfName intf @?= "HTMLElement"
          intfInherits intf @?= Just (Inheritance "Element")
        _ -> assertFailure "Expected DefInterface"

  , testCase "partial interface" $ do
      let input = "partial interface Document { attribute DOMString title; };"
      let result = parseDefinition input
      isRight result @?= True
      case result of
        Right (DefPartialInterface partial) ->
          partialIntfName partial @?= "Document"
        _ -> assertFailure "Expected DefPartialInterface"

  , testCase "interface mixin" $ do
      let input = "interface mixin DocumentOrShadowRoot {};"
      let result = parseDefinition input
      isRight result @?= True
      case result of
        Right (DefMixin mixin) ->
          mixinName mixin @?= "DocumentOrShadowRoot"
        _ -> assertFailure "Expected DefMixin"

  , testCase "includes statement" $ do
      let input = "Document includes DocumentOrShadowRoot;"
      let result = parseDefinition input
      isRight result @?= True
      case result of
        Right (DefIncludes target mixin) -> do
          target @?= "Document"
          mixin @?= "DocumentOrShadowRoot"
        _ -> assertFailure "Expected DefIncludes"
  ]


operationTests :: TestTree
operationTests = testGroup "Operation parsing"
  [ testCase "simple operation" $ do
      let input = "interface Node { Node cloneNode(); };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) -> do
          length (intfMembers intf) @?= 1
          case head (intfMembers intf) of
            IMOperation op -> do
              opName op @?= Just "cloneNode"
              opArguments op @?= []
            _ -> assertFailure "Expected IMOperation"
        _ -> assertFailure "Expected DefInterface"

  , testCase "operation with arguments" $ do
      let input = "interface Element { Element? querySelector(DOMString selectors); };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMOperation op -> do
              opName op @?= Just "querySelector"
              length (opArguments op) @?= 1
              argName (head (opArguments op)) @?= "selectors"
            _ -> assertFailure "Expected IMOperation"
        _ -> assertFailure "Expected DefInterface"

  , testCase "operation with optional argument" $ do
      let input = "interface Node { void normalize(optional boolean deep = true); };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMOperation op -> do
              length (opArguments op) @?= 1
              let arg = head (opArguments op)
              argOptional arg @?= True
              argDefault arg @?= Just (DVBool True)
            _ -> assertFailure "Expected IMOperation"
        _ -> assertFailure "Expected DefInterface"

  , testCase "getter operation" $ do
      let input = "interface HTMLCollection { getter Element? item(unsigned long index); };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMOperation op ->
              opSpecial op @?= Just SpecialGetter
            _ -> assertFailure "Expected IMOperation"
        _ -> assertFailure "Expected DefInterface"

  , testCase "static operation" $ do
      let input = "interface URL { static boolean canParse(USVString url); };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMStaticMember (IMOperation op) ->
              opName op @?= Just "canParse"
            _ -> assertFailure "Expected IMStaticMember"
        _ -> assertFailure "Expected DefInterface"
  ]


attributeTests :: TestTree
attributeTests = testGroup "Attribute parsing"
  [ testCase "simple attribute" $ do
      let input = "interface Element { attribute DOMString id; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr -> do
              attrName attr @?= "id"
              attrReadonly attr @?= False
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"

  , testCase "readonly attribute" $ do
      let input = "interface Node { readonly attribute unsigned short nodeType; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr -> do
              attrName attr @?= "nodeType"
              attrReadonly attr @?= True
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"

  , testCase "inherit attribute" $ do
      let input = "interface HTMLElement { inherit attribute DOMString dir; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr -> do
              attrName attr @?= "dir"
              attrInherit attr @?= True
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"
  ]


dictionaryTests :: TestTree
dictionaryTests = testGroup "Dictionary parsing"
  [ testCase "empty dictionary" $ do
      let input = "dictionary Options {};"
      let result = parseDefinition input
      case result of
        Right (DefDictionary dict) -> do
          dictName dict @?= "Options"
          dictMembers dict @?= []
        _ -> assertFailure "Expected DefDictionary"

  , testCase "dictionary with members" $ do
      let input = "dictionary EventInit { boolean bubbles = false; boolean cancelable = false; };"
      let result = parseDefinition input
      case result of
        Right (DefDictionary dict) -> do
          dictName dict @?= "EventInit"
          length (dictMembers dict) @?= 2
        _ -> assertFailure "Expected DefDictionary"

  , testCase "required dictionary member" $ do
      let input = "dictionary RequestInit { required DOMString method; };"
      let result = parseDefinition input
      case result of
        Right (DefDictionary dict) -> do
          let member = head (dictMembers dict)
          dmRequired member @?= True
          dmName member @?= "method"
        _ -> assertFailure "Expected DefDictionary"
  ]


enumTests :: TestTree
enumTests = testGroup "Enum parsing"
  [ testCase "simple enum" $ do
      let input = "enum ReadyState { \"loading\", \"interactive\", \"complete\" };"
      let result = parseDefinition input
      case result of
        Right (DefEnum e) -> do
          enumName e @?= "ReadyState"
          enumValues e @?= ["loading", "interactive", "complete"]
        _ -> assertFailure "Expected DefEnum"
  ]


typedefTests :: TestTree
typedefTests = testGroup "Typedef parsing"
  [ testCase "simple typedef" $ do
      let input = "typedef sequence<DOMString> StringList;"
      let result = parseDefinition input
      case result of
        Right (DefTypedef td) -> do
          typedefName td @?= "StringList"
        _ -> assertFailure "Expected DefTypedef"

  , testCase "union typedef" $ do
      let input = "typedef (DOMString or long) StringOrNumber;"
      let result = parseDefinition input
      case result of
        Right (DefTypedef td) ->
          typedefName td @?= "StringOrNumber"
        _ -> assertFailure "Expected DefTypedef"
  ]


typeTests :: TestTree
typeTests = testGroup "Type parsing"
  [ testCase "primitive types" $ do
      let input = "interface Test { attribute boolean flag; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr ->
              attrType attr @?= TyPrimitive PrimBoolean
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"

  , testCase "nullable type" $ do
      let input = "interface Test { attribute DOMString? name; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr ->
              attrType attr @?= TyNullable (TyString StrDOMString)
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"

  , testCase "sequence type" $ do
      let input = "interface Test { attribute sequence<Element> children; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr ->
              attrType attr @?= TySequence (TyIdentifier "Element")
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"

  , testCase "Promise type" $ do
      let input = "interface Test { Promise<Response> fetch(); };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMOperation op ->
              opReturnType op @?= TyPromise (TyIdentifier "Response")
            _ -> assertFailure "Expected IMOperation"
        _ -> assertFailure "Expected DefInterface"

  , testCase "record type" $ do
      let input = "interface Test { attribute record<DOMString, any> headers; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr ->
              attrType attr @?= TyRecord StrDOMString TyAny
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"

  , testCase "union type" $ do
      let input = "interface Test { attribute (DOMString or Blob) data; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr ->
              attrType attr @?= TyUnion [TyString StrDOMString, TyIdentifier "Blob"]
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"

  , testCase "buffer types" $ do
      let input = "interface Test { attribute ArrayBuffer buffer; };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMAttribute attr ->
              attrType attr @?= TyBuffer BufArrayBuffer
            _ -> assertFailure "Expected IMAttribute"
        _ -> assertFailure "Expected DefInterface"
  ]


extendedAttributeTests :: TestTree
extendedAttributeTests = testGroup "Extended attribute parsing"
  [ testCase "no-args extended attribute" $ do
      let input = "[Exposed=Window] interface Element {};"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) -> do
          length (intfExtended intf) @?= 1
          case head (intfExtended intf) of
            EAIdent name val -> do
              name @?= "Exposed"
              val @?= "Window"
            _ -> assertFailure "Expected EAIdent"
        _ -> assertFailure "Expected DefInterface"

  , testCase "multiple extended attributes" $ do
      let input = "[Exposed=Window, SecureContext] interface Credentials {};"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          length (intfExtended intf) @?= 2
        _ -> assertFailure "Expected DefInterface"

  , testCase "constructor extended attribute" $ do
      let input = "interface Element { constructor(); };"
      let result = parseDefinition input
      case result of
        Right (DefInterface intf) ->
          case head (intfMembers intf) of
            IMConstructor ctor ->
              ctorArguments ctor @?= []
            _ -> assertFailure "Expected IMConstructor"
        _ -> assertFailure "Expected DefInterface"
  ]
