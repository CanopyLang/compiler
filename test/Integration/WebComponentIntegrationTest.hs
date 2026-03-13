{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests for the Web Component generation pipeline.
--
-- Tests the full pipeline from 'WebComponentConfig' through to generated
-- JavaScript output, verifying:
--
--   * Complete Custom Element class structure
--   * ARIA attribute forwarding end-to-end
--   * Port event subscription and unsubscription lifecycle
--   * Form-associated lifecycle callbacks
--   * Typed attribute coercion in callbacks
--   * Component registration
--
-- @since 0.20.1
module Integration.WebComponentIntegrationTest (tests) where

import qualified Canopy.Data.Name as Name
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BSL
import Generate.JavaScript.WebComponent
  ( AttrCoercion (..),
    FlagAttr (..),
    PortEvent (..),
    WebComponentConfig (..),
    generateRegistration,
    generateWebComponent,
    moduleToTagName,
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup
    "WebComponent Integration"
    [ fullPipelineTest,
      ariaEndToEndTest,
      portLifecycleTest,
      formAssociatedPipelineTest,
      typedAttrsWithPortsTest,
      registrationPipelineTest
    ]

-- | Test a complete component with typed attrs, ports, and form association.
fullPipelineTest :: TestTree
fullPipelineTest =
  HUnit.testCase "full pipeline: attrs + ports + form produces complete class" $
    let config =
          WebComponentConfig
            { _wcModuleName = Name.fromChars "App.FormInput",
              _wcFlagAttrs =
                [ FlagAttr "label" "label" CoerceString,
                  FlagAttr "maxLength" "max-length" CoerceInt,
                  FlagAttr "required" "required" CoerceBool
                ],
              _wcPortEvents =
                [ PortEvent "onValidate" "validate",
                  PortEvent "onChange" "change"
                ],
              _wcFormAssociated = True
            }
        output = toStr (generateWebComponent config)
     in do
          HUnit.assertBool "extends HTMLElement"
            (isIn "extends HTMLElement" output)
          HUnit.assertBool "has static formAssociated"
            (isIn "static formAssociated = true" output)
          HUnit.assertBool "attaches internals"
            (isIn "this.attachInternals()" output)
          HUnit.assertBool "has shadow DOM"
            (isIn "this.attachShadow" output)
          HUnit.assertBool "has connectedCallback"
            (isIn "connectedCallback()" output)
          HUnit.assertBool "has disconnectedCallback"
            (isIn "disconnectedCallback()" output)
          HUnit.assertBool "has attributeChangedCallback"
            (isIn "attributeChangedCallback(" output)
          HUnit.assertBool "has formStateRestoreCallback"
            (isIn "formStateRestoreCallback(state, mode)" output)
          HUnit.assertBool "has formResetCallback"
            (isIn "formResetCallback()" output)
          HUnit.assertBool "has formDisabledCallback"
            (isIn "formDisabledCallback(disabled)" output)
          HUnit.assertBool "has observedAttributes"
            (isIn "observedAttributes" output)
          HUnit.assertBool "coerces maxLength as int"
            (isIn "parseInt(" output)
          HUnit.assertBool "coerces required as bool"
            (isIn "!== null" output)
          HUnit.assertBool "subscribes onValidate port"
            (isIn "ports.onValidate" output)
          HUnit.assertBool "subscribes onChange port"
            (isIn "ports.onChange" output)

-- | Test ARIA forwarding works end-to-end across connected and attribute callbacks.
ariaEndToEndTest :: TestTree
ariaEndToEndTest =
  HUnit.testCase "ARIA forwarding in both connectedCallback and attributeChangedCallback" $
    let config =
          WebComponentConfig
            { _wcModuleName = Name.fromChars "App.Accessible",
              _wcFlagAttrs = [FlagAttr "count" "count" CoerceInt],
              _wcPortEvents = [],
              _wcFormAssociated = False
            }
        output = toStr (generateWebComponent config)
        connBlock = takeBlock "  connectedCallback()" output
        attrBlock = takeBlock "  attributeChangedCallback(" output
     in do
          HUnit.assertBool "connected: forwards aria attributes"
            (isIn "attr.name.startsWith('aria-')" connBlock)
          HUnit.assertBool "connected: forwards role"
            (isIn "attr.name === 'role'" connBlock)
          HUnit.assertBool "connected: sets on container"
            (isIn "container.setAttribute(attr.name, attr.value)" connBlock)
          HUnit.assertBool "callback: checks aria prefix"
            (isIn "name.startsWith('aria-')" attrBlock)
          HUnit.assertBool "callback: sets on shadow container"
            (isIn "container.setAttribute(name, newValue)" attrBlock)

-- | Test port subscription in connected and unsubscription in disconnected.
portLifecycleTest :: TestTree
portLifecycleTest =
  HUnit.testCase "ports: subscribe in connected, unsubscribe in disconnected" $
    let config =
          WebComponentConfig
            { _wcModuleName = Name.fromChars "App.Chat",
              _wcFlagAttrs = [],
              _wcPortEvents =
                [ PortEvent "onMessage" "message",
                  PortEvent "onTyping" "typing"
                ],
              _wcFormAssociated = False
            }
        output = toStr (generateWebComponent config)
        connBlock = takeBlock "  connectedCallback()" output
        discBlock = takeBlock "  disconnectedCallback()" output
     in do
          HUnit.assertBool "connected: subscribes onMessage"
            (isIn "ports.onMessage" connBlock)
          HUnit.assertBool "connected: subscribes onTyping"
            (isIn "ports.onTyping" connBlock)
          HUnit.assertBool "connected: dispatches CustomEvent for message"
            (isIn "new CustomEvent('message'" connBlock)
          HUnit.assertBool "connected: dispatches CustomEvent for typing"
            (isIn "new CustomEvent('typing'" connBlock)
          HUnit.assertBool "disconnected: unsubscribes onMessage"
            (isIn "ports.onMessage.unsubscribe" discBlock)
          HUnit.assertBool "disconnected: unsubscribes onTyping"
            (isIn "ports.onTyping.unsubscribe" discBlock)
          HUnit.assertBool "disconnected: clears handlers"
            (isIn "this._handlers = {}" discBlock)

-- | Test the complete form-associated lifecycle pipeline.
formAssociatedPipelineTest :: TestTree
formAssociatedPipelineTest =
  HUnit.testCase "form-associated: full lifecycle with internals API" $
    let config =
          WebComponentConfig
            { _wcModuleName = Name.fromChars "App.DatePicker",
              _wcFlagAttrs = [FlagAttr "value" "value" CoerceString],
              _wcPortEvents = [PortEvent "onSelect" "select"],
              _wcFormAssociated = True
            }
        output = toStr (generateWebComponent config)
        ctorBlock = takeBlock "  constructor()" output
        restoreBlock = takeBlock "  formStateRestoreCallback(" output
        resetBlock = takeBlock "  formResetCallback()" output
        disabledBlock = takeBlock "  formDisabledCallback(" output
     in do
          HUnit.assertBool "constructor: has internals"
            (isIn "this._internals = this.attachInternals()" ctorBlock)
          HUnit.assertBool "restore: sends state and mode to port"
            (isIn "onFormStateRestore.send({ state: state, mode: mode })" restoreBlock)
          HUnit.assertBool "restore: sets form value via internals"
            (isIn "this._internals.setFormValue(state)" restoreBlock)
          HUnit.assertBool "reset: sends null to port"
            (isIn "onFormReset.send(null)" resetBlock)
          HUnit.assertBool "reset: clears form value"
            (isIn "this._internals.setFormValue('')" resetBlock)
          HUnit.assertBool "disabled: sends disabled flag to port"
            (isIn "onFormDisabled.send(disabled)" disabledBlock)

-- | Test that typed attributes work correctly alongside port events.
typedAttrsWithPortsTest :: TestTree
typedAttrsWithPortsTest =
  HUnit.testCase "typed attrs coerce correctly in attributeChangedCallback" $
    let config =
          WebComponentConfig
            { _wcModuleName = Name.fromChars "App.Slider",
              _wcFlagAttrs =
                [ FlagAttr "min" "min" CoerceInt,
                  FlagAttr "max" "max" CoerceInt,
                  FlagAttr "step" "step" CoerceFloat,
                  FlagAttr "disabled" "disabled" CoerceBool
                ],
              _wcPortEvents = [PortEvent "onSlide" "slide"],
              _wcFormAssociated = False
            }
        output = toStr (generateWebComponent config)
        attrBlock = takeBlock "  attributeChangedCallback(" output
        obsBlock = takeBlock "  static get observedAttributes()" output
     in do
          HUnit.assertBool "coerces min as int"
            (isIn "name === 'min') coerced = parseInt(newValue, 10)" attrBlock)
          HUnit.assertBool "coerces step as float"
            (isIn "name === 'step') coerced = parseFloat(newValue)" attrBlock)
          HUnit.assertBool "coerces disabled as bool"
            (isIn "name === 'disabled') coerced = newValue !== null" attrBlock)
          HUnit.assertBool "observes all four attributes"
            (isIn "'min', 'max', 'step', 'disabled'" obsBlock)

-- | Test registration call matches the class name from tag.
registrationPipelineTest :: TestTree
registrationPipelineTest =
  HUnit.testCase "registration call matches generated class" $
    let modName = Name.fromChars "App.DatePicker"
        tagName = moduleToTagName modName
        regOutput = toStr (generateRegistration modName)
     in do
          tagName @?= "app-date-picker"
          regOutput @?= "customElements.define('app-date-picker', AppDatePicker);\n"


-- Helpers

toStr :: BB.Builder -> String
toStr = BSL.unpack . BB.toLazyByteString

isIn :: String -> String -> Bool
isIn needle haystack = any (startsWith needle) (tails haystack)
  where
    startsWith [] _ = True
    startsWith _ [] = False
    startsWith (a : as') (b : bs) = a == b && startsWith as' bs
    tails [] = [[]]
    tails s@(_ : rest) = s : tails rest

-- | Extract a block from generated output starting at a given prefix.
takeBlock :: String -> String -> String
takeBlock prefix fullOutput =
  unlines (takeWhileInclusive (not . isClosingBrace) block)
  where
    allLines = lines fullOutput
    block = dropWhile (not . hasPrefix prefix) allLines
    isClosingBrace ln = ln == "  }"
    hasPrefix p s = take (length p) s == p

-- | Take elements while predicate holds, plus the first that fails.
takeWhileInclusive :: (a -> Bool) -> [a] -> [a]
takeWhileInclusive _ [] = []
takeWhileInclusive p (x : xs)
  | p x = x : takeWhileInclusive p xs
  | otherwise = [x]
