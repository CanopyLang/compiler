{-# LANGUAGE OverloadedStrings #-}

-- | Web Component output generator.
--
-- Generates Custom Element class definitions that wrap Canopy applications
-- as Web Components. Each component:
--
--   * Extends @HTMLElement@ with Shadow DOM
--   * Maps HTML attributes to Canopy flags with type coercion
--   * Populates @observedAttributes@ from the module's flags record
--   * Dispatches typed @CustomEvent@s for outgoing ports
--   * Calls @customElements.define@ for registration
--   * Supports lifecycle callbacks for TEA integration
--
-- == Usage
--
-- In @canopy.json@:
--
-- @
-- {
--   "web-components": ["MyApp.Counter", "MyApp.TodoList"]
-- }
-- @
--
-- This generates @\<my-app-counter\>@ and @\<my-app-todo-list\>@ custom elements.
--
-- @since 0.20.0
module Generate.JavaScript.WebComponent
  ( -- * Generation
    generateWebComponent,
    generateRegistration,

    -- * Configuration
    WebComponentConfig (..),
    FlagAttr (..),
    PortEvent (..),
    AttrCoercion (..),

    -- * Tag Name Conversion
    moduleToTagName,
    camelToKebab,
  )
where

import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import Data.Char (isUpper, toLower)
import Data.List (intercalate)

-- | Configuration for generating a Web Component.
--
-- @since 0.20.1
data WebComponentConfig = WebComponentConfig
  { _wcModuleName :: !ModuleName.Raw
  , _wcFlagAttrs :: ![FlagAttr]
  , _wcPortEvents :: ![PortEvent]
  , _wcFormAssociated :: !Bool
  } deriving (Show, Eq)

-- | A flag field mapped to an HTML attribute.
--
-- @since 0.20.1
data FlagAttr = FlagAttr
  { _faFieldName :: !String
  , _faAttrName :: !String
  , _faCoercion :: !AttrCoercion
  } deriving (Show, Eq)

-- | An outgoing port mapped to a CustomEvent.
--
-- @since 0.20.1
data PortEvent = PortEvent
  { _pePortName :: !String
  , _peEventName :: !String
  } deriving (Show, Eq)

-- | How to coerce an HTML attribute string to a typed flag value.
--
-- @since 0.20.1
data AttrCoercion
  = CoerceString
  | CoerceInt
  | CoerceFloat
  | CoerceBool
  deriving (Show, Eq)

-- | Generate a Custom Element class for a Canopy module.
--
-- Accepts a 'WebComponentConfig' for rich generation with typed
-- attributes and events. Falls back to the simple variant when
-- called with the 'ModuleName.Raw' overload.
--
-- @since 0.20.0
generateWebComponent :: WebComponentConfig -> Builder
generateWebComponent config =
  classDefinition tagName jsModName attrs events formAssoc
  where
    modName = _wcModuleName config
    tagName = moduleToTagName modName
    jsModName = moduleToJsName modName
    attrs = _wcFlagAttrs config
    events = _wcPortEvents config
    formAssoc = _wcFormAssociated config

-- | Generate the @customElements.define@ registration call.
--
-- @since 0.20.0
generateRegistration :: ModuleName.Raw -> Builder
generateRegistration modName =
  BB.stringUtf8 "customElements.define('"
    <> BB.stringUtf8 (moduleToTagName modName)
    <> BB.stringUtf8 "', "
    <> BB.stringUtf8 (className modName)
    <> BB.stringUtf8 ");\n"

-- | Convert a Canopy module name to a valid custom element tag name.
--
-- Custom elements must contain a hyphen. We convert PascalCase segments
-- to kebab-case: @MyApp.Counter@ -> @my-app-counter@.
--
-- @since 0.20.0
moduleToTagName :: ModuleName.Raw -> String
moduleToTagName modName =
  intercalate "-" (map toKebab segments)
  where
    raw = Utf8.toChars modName
    segments = splitOn '.' raw
    toKebab [] = []
    toKebab (c : cs) = toLower c : concatMap expandUpper cs
    expandUpper c
      | isUpper c = ['-', toLower c]
      | otherwise = [c]

-- | Convert camelCase to kebab-case.
--
-- @initialCount@ -> @initial-count@, @isEnabled@ -> @is-enabled@.
--
-- @since 0.20.1
camelToKebab :: String -> String
camelToKebab [] = []
camelToKebab (c : cs) = toLower c : concatMap expandChar cs
  where
    expandChar x
      | isUpper x = ['-', toLower x]
      | otherwise = [x]


-- INTERNAL


-- | Generate the full class definition.
classDefinition :: String -> String -> [FlagAttr] -> [PortEvent] -> Bool -> Builder
classDefinition tagName jsModName attrs events formAssoc =
  BB.stringUtf8 "class "
    <> BB.stringUtf8 (pascalFromKebab tagName)
    <> BB.stringUtf8 " extends HTMLElement {\n"
    <> formAssociatedStatic formAssoc
    <> constructorDef
    <> connectedCallback jsModName attrs events
    <> disconnectedCallback events
    <> attributeChangedCallback attrs
    <> observedAttributes attrs
    <> BB.stringUtf8 "}\n"

-- | Generate static formAssociated property when enabled.
formAssociatedStatic :: Bool -> Builder
formAssociatedStatic False = mempty
formAssociatedStatic True =
  BB.stringUtf8 "  static formAssociated = true;\n"

-- | Generate constructor with Shadow DOM.
constructorDef :: Builder
constructorDef =
  BB.stringUtf8 "  constructor() {\n"
    <> BB.stringUtf8 "    super();\n"
    <> BB.stringUtf8 "    this._root = this.attachShadow({ mode: 'open' });\n"
    <> BB.stringUtf8 "    this._app = null;\n"
    <> BB.stringUtf8 "    this._handlers = {};\n"
    <> BB.stringUtf8 "  }\n"

-- | Generate connectedCallback with typed flag coercion and port subscriptions.
connectedCallback :: String -> [FlagAttr] -> [PortEvent] -> Builder
connectedCallback jsModName attrs events =
  BB.stringUtf8 "  connectedCallback() {\n"
    <> flagsBlock attrs
    <> BB.stringUtf8 "    var container = document.createElement('div');\n"
    <> BB.stringUtf8 "    this._root.appendChild(container);\n"
    <> BB.stringUtf8 "    this._app = "
    <> BB.stringUtf8 jsModName
    <> BB.stringUtf8 ".init({ node: container, flags: flags });\n"
    <> ariaForwarding
    <> portSubscriptions events
    <> BB.stringUtf8 "  }\n"

-- | Generate the flags object construction.
flagsBlock :: [FlagAttr] -> Builder
flagsBlock [] =
  BB.stringUtf8 "    var flags = {};\n"
    <> BB.stringUtf8 "    for (var attr of this.attributes) {\n"
    <> BB.stringUtf8 "      flags[attr.name] = attr.value;\n"
    <> BB.stringUtf8 "    }\n"
flagsBlock attrs =
  BB.stringUtf8 "    var flags = {};\n"
    <> mconcat (map coerceAttr attrs)

-- | Generate coercion code for a single attribute.
coerceAttr :: FlagAttr -> Builder
coerceAttr attr =
  BB.stringUtf8 "    flags['"
    <> BB.stringUtf8 (_faFieldName attr)
    <> BB.stringUtf8 "'] = "
    <> coercionExpr (_faCoercion attr) (BB.stringUtf8 attrGet)
    <> BB.stringUtf8 ";\n"
  where
    attrGet = "this.getAttribute('" ++ _faAttrName attr ++ "')"

-- | Generate the coercion expression for a given type.
coercionExpr :: AttrCoercion -> Builder -> Builder
coercionExpr CoerceString val = val
coercionExpr CoerceInt val = BB.stringUtf8 "parseInt(" <> val <> BB.stringUtf8 ", 10)"
coercionExpr CoerceFloat val = BB.stringUtf8 "parseFloat(" <> val <> BB.stringUtf8 ")"
coercionExpr CoerceBool val = val <> BB.stringUtf8 " !== null"

-- | Generate ARIA attribute forwarding from host to shadow container.
--
-- Forwards all @aria-*@ attributes and the @role@ attribute from the
-- host element to the shadow DOM container, ensuring screen readers
-- can access the component's semantics.
ariaForwarding :: Builder
ariaForwarding =
  BB.stringUtf8 "    for (var attr of this.attributes) {\n"
    <> BB.stringUtf8 "      if (attr.name.startsWith('aria-') || attr.name === 'role') {\n"
    <> BB.stringUtf8 "        container.setAttribute(attr.name, attr.value);\n"
    <> BB.stringUtf8 "      }\n"
    <> BB.stringUtf8 "    }\n"

-- | Generate port-to-CustomEvent subscriptions.
portSubscriptions :: [PortEvent] -> Builder
portSubscriptions [] = mempty
portSubscriptions events = mconcat (map subscribePort events)

-- | Subscribe a single port to dispatch a CustomEvent, storing the handler.
subscribePort :: PortEvent -> Builder
subscribePort event =
  BB.stringUtf8 "    if (this._app.ports && this._app.ports."
    <> BB.stringUtf8 portName
    <> BB.stringUtf8 ") {\n"
    <> BB.stringUtf8 "      var self = this;\n"
    <> BB.stringUtf8 "      this._handlers['"
    <> BB.stringUtf8 portName
    <> BB.stringUtf8 "'] = function(data) {\n"
    <> BB.stringUtf8 "        self.dispatchEvent(new CustomEvent('"
    <> BB.stringUtf8 (_peEventName event)
    <> BB.stringUtf8 "', { detail: data, bubbles: true }));\n"
    <> BB.stringUtf8 "      };\n"
    <> BB.stringUtf8 "      this._app.ports."
    <> BB.stringUtf8 portName
    <> BB.stringUtf8 ".subscribe(this._handlers['"
    <> BB.stringUtf8 portName
    <> BB.stringUtf8 "']);\n"
    <> BB.stringUtf8 "    }\n"
  where
    portName = _pePortName event

-- | Generate disconnectedCallback for cleanup.
disconnectedCallback :: [PortEvent] -> Builder
disconnectedCallback events =
  BB.stringUtf8 "  disconnectedCallback() {\n"
    <> portUnsubscriptions events
    <> BB.stringUtf8 "    this._handlers = {};\n"
    <> BB.stringUtf8 "    this._root.innerHTML = '';\n"
    <> BB.stringUtf8 "    this._app = null;\n"
    <> BB.stringUtf8 "  }\n"

-- | Generate unsubscribe calls for all port event handlers.
portUnsubscriptions :: [PortEvent] -> Builder
portUnsubscriptions [] = mempty
portUnsubscriptions events = mconcat (map unsubscribePort events)

-- | Unsubscribe a single port handler.
unsubscribePort :: PortEvent -> Builder
unsubscribePort event =
  BB.stringUtf8 "    if (this._app && this._app.ports && this._app.ports."
    <> BB.stringUtf8 portName
    <> BB.stringUtf8 " && this._handlers['"
    <> BB.stringUtf8 portName
    <> BB.stringUtf8 "']) {\n"
    <> BB.stringUtf8 "      this._app.ports."
    <> BB.stringUtf8 portName
    <> BB.stringUtf8 ".unsubscribe(this._handlers['"
    <> BB.stringUtf8 portName
    <> BB.stringUtf8 "']);\n"
    <> BB.stringUtf8 "    }\n"
  where
    portName = _pePortName event

-- | Generate attributeChangedCallback with typed coercion.
attributeChangedCallback :: [FlagAttr] -> Builder
attributeChangedCallback [] =
  BB.stringUtf8 "  attributeChangedCallback(name, oldValue, newValue) {\n"
    <> ariaCallbackForwarding
    <> BB.stringUtf8 "    if (this._app && this._app.ports && this._app.ports.onAttributeChange) {\n"
    <> BB.stringUtf8 "      this._app.ports.onAttributeChange.send({ name: name, value: newValue });\n"
    <> BB.stringUtf8 "    }\n"
    <> BB.stringUtf8 "  }\n"
attributeChangedCallback attrs =
  BB.stringUtf8 "  attributeChangedCallback(name, oldValue, newValue) {\n"
    <> ariaCallbackForwarding
    <> BB.stringUtf8 "    if (!this._app || !this._app.ports || !this._app.ports.onAttributeChange) return;\n"
    <> BB.stringUtf8 "    var coerced = newValue;\n"
    <> mconcat (map coerceInCallback attrs)
    <> BB.stringUtf8 "    this._app.ports.onAttributeChange.send({ name: name, value: coerced });\n"
    <> BB.stringUtf8 "  }\n"

-- | Generate ARIA forwarding within attributeChangedCallback.
--
-- Mirrors ARIA attribute changes from the host element to the
-- shadow container so screen readers stay synchronized.
ariaCallbackForwarding :: Builder
ariaCallbackForwarding =
  BB.stringUtf8 "    if (name.startsWith('aria-') || name === 'role') {\n"
    <> BB.stringUtf8 "      var container = this._root.firstChild;\n"
    <> BB.stringUtf8 "      if (container) container.setAttribute(name, newValue);\n"
    <> BB.stringUtf8 "    }\n"

-- | Generate a coercion branch for a single attribute in the callback.
coerceInCallback :: FlagAttr -> Builder
coerceInCallback attr =
  BB.stringUtf8 "    if (name === '"
    <> BB.stringUtf8 (_faAttrName attr)
    <> BB.stringUtf8 "') coerced = "
    <> coercionExpr (_faCoercion attr) (BB.stringUtf8 "newValue")
    <> BB.stringUtf8 ";\n"

-- | Generate static observedAttributes getter from flag attributes.
observedAttributes :: [FlagAttr] -> Builder
observedAttributes [] =
  BB.stringUtf8 "  static get observedAttributes() { return []; }\n"
observedAttributes attrs =
  BB.stringUtf8 "  static get observedAttributes() { return ["
    <> attrList
    <> BB.stringUtf8 "]; }\n"
  where
    attrList = mconcat (intersperse (BB.stringUtf8 ", ") quoted)
    quoted = map (\a -> BB.stringUtf8 "'" <> BB.stringUtf8 (_faAttrName a) <> BB.stringUtf8 "'") attrs

-- | Convert a module name to a JavaScript module reference.
moduleToJsName :: ModuleName.Raw -> String
moduleToJsName modName =
  map replaceDot (Utf8.toChars modName)
  where
    replaceDot '.' = '$'
    replaceDot c = c

-- | Generate the class name from a module.
className :: ModuleName.Raw -> String
className modName = pascalFromKebab (moduleToTagName modName)

-- | Convert kebab-case to PascalCase.
pascalFromKebab :: String -> String
pascalFromKebab = concatMap capitalize . splitOn '-'
  where
    capitalize [] = []
    capitalize (c : cs) = toUpper c : cs
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c

-- | Split a string on a delimiter character.
splitOn :: Char -> String -> [String]
splitOn _ [] = []
splitOn delim s =
  case break (== delim) s of
    (before, []) -> [before]
    (before, _ : rest) -> before : splitOn delim rest

-- | Intersperse a separator between builder elements.
intersperse :: Builder -> [Builder] -> [Builder]
intersperse _ [] = []
intersperse _ [x] = [x]
intersperse sep (x : xs) = x : sep : intersperse sep xs
