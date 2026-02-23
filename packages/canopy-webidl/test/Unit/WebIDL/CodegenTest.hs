{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Code Generation Tests
--
-- Tests for Canopy and JavaScript code generation.
--
-- @since 0.20.0
module Unit.WebIDL.CodegenTest (tests) where

import qualified Data.Text as Text
import Test.Tasty
import Test.Tasty.HUnit

import WebIDL.Config
import WebIDL.Transform
import qualified WebIDL.Codegen.Canopy as Canopy
import qualified WebIDL.Codegen.JavaScript as JavaScript


tests :: TestTree
tests = testGroup "WebIDL.Codegen"
  [ canopyTypeRenderingTests
  , canopyFunctionTests
  , canopyRecordTests
  , javaScriptTests
  ]


canopyTypeRenderingTests :: TestTree
canopyTypeRenderingTests = testGroup "Canopy type rendering"
  [ testCase "renderType Int" $
      Canopy.renderType CTInt @?= "Int"

  , testCase "renderType Float" $
      Canopy.renderType CTFloat @?= "Float"

  , testCase "renderType Bool" $
      Canopy.renderType CTBool @?= "Bool"

  , testCase "renderType String" $
      Canopy.renderType CTString @?= "String"

  , testCase "renderType Unit" $
      Canopy.renderType CTUnit @?= "()"

  , testCase "renderType Maybe Int" $
      Canopy.renderType (CTMaybe CTInt) @?= "Maybe Int"

  , testCase "renderType List String" $
      Canopy.renderType (CTList CTString) @?= "List String"

  , testCase "renderType Task Error Response" $
      Canopy.renderType (CTTask (CTCustom "Error") (CTCustom "Response"))
        @?= "Task Error Response"

  , testCase "renderType Dict String Int" $
      Canopy.renderType (CTDict CTString CTInt)
        @?= "Dict String Int"

  , testCase "renderType nested Maybe List" $
      Canopy.renderType (CTMaybe (CTList CTString))
        @?= "Maybe (List String)"

  , testCase "renderType Custom type" $
      Canopy.renderType (CTCustom "Element") @?= "Element"
  ]


canopyFunctionTests :: TestTree
canopyFunctionTests = testGroup "Canopy function rendering"
  [ testCase "renderTypeAnnotation simple getter" $ do
      let func = CanopyFunction
            { cfName = "id"
            , cfDoc = Nothing
            , cfParams = [("self", CTCustom "Element")]
            , cfReturn = CTString
            , cfIsStatic = False
            , cfJsName = "id"
            , cfJsTarget = Just "Element"
            }
      let result = Canopy.renderTypeAnnotation func
      result @?= "id : Element -> String"

  , testCase "renderTypeAnnotation with multiple params" $ do
      let func = CanopyFunction
            { cfName = "setAttribute"
            , cfDoc = Nothing
            , cfParams =
                [ ("self", CTCustom "Element")
                , ("name", CTString)
                , ("value", CTString)
                ]
            , cfReturn = CTUnit
            , cfIsStatic = False
            , cfJsName = "setAttribute"
            , cfJsTarget = Just "Element"
            }
      let result = Canopy.renderTypeAnnotation func
      result @?= "setAttribute : Element -> String -> String -> ()"

  , testCase "renderTypeAnnotation with Task return" $ do
      let func = CanopyFunction
            { cfName = "fetch"
            , cfDoc = Nothing
            , cfParams = [("url", CTString)]
            , cfReturn = CTTask (CTCustom "Error") (CTCustom "Response")
            , cfIsStatic = True
            , cfJsName = "fetch"
            , cfJsTarget = Nothing
            }
      let result = Canopy.renderTypeAnnotation func
      result @?= "fetch : String -> Task Error Response"

  , testCase "renderFunction includes FFI call" $ do
      let func = CanopyFunction
            { cfName = "getElementById"
            , cfDoc = Nothing
            , cfParams =
                [ ("self", CTCustom "Document")
                , ("id", CTString)
                ]
            , cfReturn = CTMaybe (CTCustom "Element")
            , cfIsStatic = False
            , cfJsName = "getElementById"
            , cfJsTarget = Just "Document"
            }
      let result = Canopy.renderFunction defaultConfig func
      assertBool "contains function name" (Text.isInfixOf "getElementById" result)
      assertBool "contains Native call" (Text.isInfixOf "Native." result)
  ]


canopyRecordTests :: TestTree
canopyRecordTests = testGroup "Canopy record rendering"
  [ testCase "renderRecord simple record" $ do
      let record = CanopyRecord
            { crName = "EventInit"
            , crDoc = Nothing
            , crFields =
                [ CanopyField "bubbles" CTBool False Nothing
                , CanopyField "cancelable" CTBool False Nothing
                ]
            }
      let result = Canopy.renderRecord record
      assertBool "contains type alias" (Text.isInfixOf "type alias EventInit" result)
      assertBool "contains bubbles field" (Text.isInfixOf "bubbles : Bool" result)
      assertBool "contains cancelable field" (Text.isInfixOf "cancelable : Bool" result)
  ]


javaScriptTests :: TestTree
javaScriptTests = testGroup "JavaScript rendering"
  [ testCase "renderToJs for Maybe" $ do
      let result = JavaScript.renderToJs (CTMaybe CTString) "value"
      result @?= "_fromMaybe(value, null)"

  , testCase "renderToJs for List" $ do
      let result = JavaScript.renderToJs (CTList CTInt) "items"
      result @?= "_List_toArray(items)"

  , testCase "renderToJs for plain type" $ do
      let result = JavaScript.renderToJs CTString "str"
      result @?= "str"

  , testCase "renderFromJs for Maybe" $ do
      let result = JavaScript.renderFromJs (CTMaybe CTString) "value"
      result @?= "_toMaybe(value)"

  , testCase "renderFromJs for List" $ do
      let result = JavaScript.renderFromJs (CTList CTInt) "array"
      result @?= "_List_fromArray(array)"

  , testCase "renderFromJs for Task" $ do
      let result = JavaScript.renderFromJs (CTTask (CTCustom "Error") CTString) "promise"
      result @?= "_Task_fromPromise(promise)"

  , testCase "renderGetter produces valid JS" $ do
      let func = CanopyFunction
            { cfName = "id"
            , cfDoc = Nothing
            , cfParams = [("self", CTCustom "Element")]
            , cfReturn = CTString
            , cfIsStatic = False
            , cfJsName = "id"
            , cfJsTarget = Just "Element"
            }
      let result = JavaScript.renderGetter func
      assertBool "contains function keyword" (Text.isInfixOf "function" result)
      assertBool "contains self parameter" (Text.isInfixOf "self" result)
      assertBool "contains property access" (Text.isInfixOf "self.id" result)

  , testCase "renderSetter produces valid JS" $ do
      let func = CanopyFunction
            { cfName = "setId"
            , cfDoc = Nothing
            , cfParams =
                [ ("self", CTCustom "Element")
                , ("value", CTString)
                ]
            , cfReturn = CTUnit
            , cfIsStatic = False
            , cfJsName = "setId"
            , cfJsTarget = Just "Element"
            }
      let result = JavaScript.renderSetter func
      assertBool "contains F2" (Text.isInfixOf "F2" result)
      assertBool "contains assignment" (Text.isInfixOf "=" result)

  , testCase "renderConstructor produces new keyword" $ do
      let func = CanopyFunction
            { cfName = "newElement"
            , cfDoc = Nothing
            , cfParams = [("tagName", CTString)]
            , cfReturn = CTCustom "Element"
            , cfIsStatic = True
            , cfJsName = "Element"
            , cfJsTarget = Just "Element"
            }
      let result = JavaScript.renderConstructor func
      assertBool "contains new keyword" (Text.isInfixOf "new " result)
  ]
