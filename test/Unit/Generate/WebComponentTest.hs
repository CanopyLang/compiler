{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Web Component generation.
--
-- Tests tag name conversion, camelToKebab, and the full
-- 'generateWebComponent' and 'generateRegistration' output
-- including port event handler lifecycle.
--
-- @since 0.20.1
module Unit.Generate.WebComponentTest
  ( tests
  ) where

import qualified Canopy.Data.Name as Name
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BSL
import Generate.JavaScript.WebComponent
  ( AttrCoercion (..),
    FlagAttr (..),
    PortEvent (..),
    WebComponentConfig (..),
    camelToKebab,
    generateRegistration,
    generateWebComponent,
    moduleToTagName
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

builderToString :: BB.Builder -> String
builderToString = BSL.unpack . BB.toLazyByteString

tests :: TestTree
tests =
  Test.testGroup
    "Generate.JavaScript.WebComponent"
    [ tagNameTests,
      camelToKebabTests,
      emptyComponentTest,
      portEventHandlerTests,
      registrationTest,
      ariaForwardingTests,
      formAssociatedTests
    ]

tagNameTests :: TestTree
tagNameTests =
  Test.testGroup
    "moduleToTagName"
    [ HUnit.testCase "converts MyApp.Counter to my-app-counter" $
        moduleToTagName (Name.fromChars "MyApp.Counter") @?= "my-app-counter",
      HUnit.testCase "converts single module name" $
        moduleToTagName (Name.fromChars "Counter") @?= "counter",
      HUnit.testCase "converts three segments" $
        moduleToTagName (Name.fromChars "My.Todo.List") @?= "my-todo-list"
    ]

camelToKebabTests :: TestTree
camelToKebabTests =
  Test.testGroup
    "camelToKebab"
    [ HUnit.testCase "converts initialCount to initial-count" $
        camelToKebab "initialCount" @?= "initial-count",
      HUnit.testCase "converts isEnabled to is-enabled" $
        camelToKebab "isEnabled" @?= "is-enabled",
      HUnit.testCase "preserves lowercase" $
        camelToKebab "name" @?= "name",
      HUnit.testCase "handles empty string" $
        camelToKebab "" @?= ""
    ]

emptyComponentTest :: TestTree
emptyComponentTest =
  HUnit.testCase "empty attrs/events produces valid class with lifecycle methods" $
    let config = WebComponentConfig
          { _wcModuleName = Name.fromChars "MyApp.Counter"
          , _wcFlagAttrs = []
          , _wcPortEvents = []
          , _wcFormAssociated = False
          }
        output = builderToString (generateWebComponent config)
     in output
          @?= "class MyAppCounter extends HTMLElement {\n"
          ++ "  constructor() {\n"
          ++ "    super();\n"
          ++ "    this._root = this.attachShadow({ mode: 'open' });\n"
          ++ "    this._app = null;\n"
          ++ "    this._handlers = {};\n"
          ++ "  }\n"
          ++ "  connectedCallback() {\n"
          ++ "    var flags = {};\n"
          ++ "    for (var attr of this.attributes) {\n"
          ++ "      flags[attr.name] = attr.value;\n"
          ++ "    }\n"
          ++ "    var container = document.createElement('div');\n"
          ++ "    this._root.appendChild(container);\n"
          ++ "    this._app = MyApp$Counter.init({ node: container, flags: flags });\n"
          ++ "    for (var attr of this.attributes) {\n"
          ++ "      if (attr.name.startsWith('aria-') || attr.name === 'role') {\n"
          ++ "        container.setAttribute(attr.name, attr.value);\n"
          ++ "      }\n"
          ++ "    }\n"
          ++ "  }\n"
          ++ "  disconnectedCallback() {\n"
          ++ "    this._handlers = {};\n"
          ++ "    this._root.innerHTML = '';\n"
          ++ "    this._app = null;\n"
          ++ "  }\n"
          ++ "  attributeChangedCallback(name, oldValue, newValue) {\n"
          ++ "    if (name.startsWith('aria-') || name === 'role') {\n"
          ++ "      var container = this._root.firstChild;\n"
          ++ "      if (container) container.setAttribute(name, newValue);\n"
          ++ "    }\n"
          ++ "    if (this._app && this._app.ports && this._app.ports.onAttributeChange) {\n"
          ++ "      this._app.ports.onAttributeChange.send({ name: name, value: newValue });\n"
          ++ "    }\n"
          ++ "  }\n"
          ++ "  static get observedAttributes() { return []; }\n"
          ++ "}\n"

portEventHandlerTests :: TestTree
portEventHandlerTests =
  Test.testGroup
    "PortEvent handling"
    [ portConstructorTest,
      portDisconnectedTest
    ]

portConstructorTest :: TestTree
portConstructorTest =
  HUnit.testCase "component with PortEvents includes this._handlers in constructor" $
    let config = WebComponentConfig
          { _wcModuleName = Name.fromChars "App.Chat"
          , _wcFlagAttrs = []
          , _wcPortEvents = [PortEvent "onMessage" "message"]
          , _wcFormAssociated = False
          }
        output = builderToString (generateWebComponent config)
        constructorBlock =
             "  constructor() {\n"
          ++ "    super();\n"
          ++ "    this._root = this.attachShadow({ mode: 'open' });\n"
          ++ "    this._app = null;\n"
          ++ "    this._handlers = {};\n"
          ++ "  }\n"
     in takeBlock "  constructor()" output @?= constructorBlock

portDisconnectedTest :: TestTree
portDisconnectedTest =
  HUnit.testCase "component with PortEvents includes unsubscribe in disconnectedCallback" $
    let config = WebComponentConfig
          { _wcModuleName = Name.fromChars "App.Chat"
          , _wcFlagAttrs = []
          , _wcPortEvents = [PortEvent "onMessage" "message"]
          , _wcFormAssociated = False
          }
        output = builderToString (generateWebComponent config)
        disconnectedBlock =
             "  disconnectedCallback() {\n"
          ++ "    if (this._app && this._app.ports && this._app.ports.onMessage && this._handlers['onMessage']) {\n"
          ++ "      this._app.ports.onMessage.unsubscribe(this._handlers['onMessage']);\n"
          ++ "    }\n"
          ++ "    this._handlers = {};\n"
          ++ "    this._root.innerHTML = '';\n"
          ++ "    this._app = null;\n"
          ++ "  }\n"
     in takeBlock "  disconnectedCallback()" output @?= disconnectedBlock

registrationTest :: TestTree
registrationTest =
  HUnit.testCase "generateRegistration produces customElements.define call" $
    let output = builderToString (generateRegistration (Name.fromChars "MyApp.Counter"))
     in output @?= "customElements.define('my-app-counter', MyAppCounter);\n"

ariaForwardingTests :: TestTree
ariaForwardingTests =
  Test.testGroup
    "ARIA attribute forwarding"
    [ ariaConnectedTest,
      ariaCallbackEmptyAttrsTest,
      ariaCallbackWithAttrsTest
    ]

ariaConnectedTest :: TestTree
ariaConnectedTest =
  HUnit.testCase "connectedCallback forwards aria-* and role to shadow container" $
    let config = WebComponentConfig
          { _wcModuleName = Name.fromChars "App.Widget"
          , _wcFlagAttrs = []
          , _wcPortEvents = []
          , _wcFormAssociated = False
          }
        output = builderToString (generateWebComponent config)
        connectedBlock = takeBlock "  connectedCallback()" output
     in do
          HUnit.assertBool "contains aria forwarding loop"
            ("for (var attr of this.attributes)" `isIn` connectedBlock)
          HUnit.assertBool "checks aria- prefix"
            ("attr.name.startsWith('aria-')" `isIn` connectedBlock)
          HUnit.assertBool "checks role attribute"
            ("attr.name === 'role'" `isIn` connectedBlock)
          HUnit.assertBool "sets attribute on container"
            ("container.setAttribute(attr.name, attr.value)" `isIn` connectedBlock)

ariaCallbackEmptyAttrsTest :: TestTree
ariaCallbackEmptyAttrsTest =
  HUnit.testCase "attributeChangedCallback with no attrs forwards ARIA changes" $
    let config = WebComponentConfig
          { _wcModuleName = Name.fromChars "App.Widget"
          , _wcFlagAttrs = []
          , _wcPortEvents = []
          , _wcFormAssociated = False
          }
        output = builderToString (generateWebComponent config)
        callbackBlock = takeBlock "  attributeChangedCallback(" output
     in do
          HUnit.assertBool "checks aria- prefix"
            ("name.startsWith('aria-')" `isIn` callbackBlock)
          HUnit.assertBool "checks role attribute"
            ("name === 'role'" `isIn` callbackBlock)
          HUnit.assertBool "forwards to shadow container"
            ("container.setAttribute(name, newValue)" `isIn` callbackBlock)

ariaCallbackWithAttrsTest :: TestTree
ariaCallbackWithAttrsTest =
  HUnit.testCase "attributeChangedCallback with typed attrs still forwards ARIA changes" $
    let config = WebComponentConfig
          { _wcModuleName = Name.fromChars "App.Widget"
          , _wcFlagAttrs = [FlagAttr "count" "count" CoerceInt]
          , _wcPortEvents = []
          , _wcFormAssociated = False
          }
        output = builderToString (generateWebComponent config)
        callbackBlock = takeBlock "  attributeChangedCallback(" output
     in do
          HUnit.assertBool "checks aria- prefix"
            ("name.startsWith('aria-')" `isIn` callbackBlock)
          HUnit.assertBool "forwards to shadow container"
            ("container.setAttribute(name, newValue)" `isIn` callbackBlock)
          HUnit.assertBool "still coerces typed attrs"
            ("parseInt(newValue, 10)" `isIn` callbackBlock)

formAssociatedTests :: TestTree
formAssociatedTests =
  Test.testGroup
    "formAssociated static property"
    [ formAssociatedEnabledTest,
      formAssociatedDisabledTest
    ]

formAssociatedEnabledTest :: TestTree
formAssociatedEnabledTest =
  HUnit.testCase "generates static formAssociated = true when enabled" $
    let config = WebComponentConfig
          { _wcModuleName = Name.fromChars "App.Input"
          , _wcFlagAttrs = []
          , _wcPortEvents = []
          , _wcFormAssociated = True
          }
        output = builderToString (generateWebComponent config)
     in HUnit.assertBool "contains formAssociated static"
          ("static formAssociated = true;" `isIn` output)

formAssociatedDisabledTest :: TestTree
formAssociatedDisabledTest =
  HUnit.testCase "omits static formAssociated when disabled" $
    let config = WebComponentConfig
          { _wcModuleName = Name.fromChars "App.Display"
          , _wcFlagAttrs = []
          , _wcPortEvents = []
          , _wcFormAssociated = False
          }
        output = builderToString (generateWebComponent config)
     in HUnit.assertBool "does not contain formAssociated"
          (not ("formAssociated" `isIn` output))

-- | Check if a substring appears in a string.
isIn :: String -> String -> Bool
isIn needle haystack = any (startsWith needle) (tails haystack)
  where
    startsWith [] _ = True
    startsWith _ [] = False
    startsWith (n : ns) (h : hs) = n == h && startsWith ns hs
    tails [] = [[]]
    tails s@(_ : rest) = s : tails rest

-- | Extract a block from generated output starting at a given prefix
-- through its closing brace line.
takeBlock :: String -> String -> String
takeBlock prefix fullOutput =
  unlines (takeWhileInclusive (not . isClosingBrace) block)
  where
    allLines = lines fullOutput
    block = dropWhile (not . startsWith prefix) allLines
    isClosingBrace ln = ln == "  }"
    startsWith p s = take (length p) s == p

-- | Take elements while predicate holds, plus the first element that fails.
takeWhileInclusive :: (a -> Bool) -> [a] -> [a]
takeWhileInclusive _ [] = []
takeWhileInclusive p (x : xs)
  | p x = x : takeWhileInclusive p xs
  | otherwise = [x]
