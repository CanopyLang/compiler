{-# LANGUAGE OverloadedStrings #-}

-- | Web Component output generator.
--
-- Generates Custom Element class definitions that wrap Canopy applications
-- as Web Components. Each component:
--
--   * Extends @HTMLElement@ with Shadow DOM
--   * Maps HTML attributes to Canopy flags
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

    -- * Tag Name Conversion
    moduleToTagName,
  )
where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Data.Utf8 as Utf8
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BB
import Data.Char (isUpper, toLower)
import Data.List (intercalate)

-- | Generate a Custom Element class for a Canopy module.
--
-- The generated class:
--
--   1. Creates a Shadow DOM root in the constructor
--   2. Initializes the Canopy app in @connectedCallback@
--   3. Cleans up in @disconnectedCallback@
--   4. Maps observed attributes to flags
--
-- @since 0.20.0
generateWebComponent :: ModuleName.Raw -> Builder
generateWebComponent modName =
  classDefinition tagName jsModName
  where
    tagName = moduleToTagName modName
    jsModName = moduleToJsName modName

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
-- to kebab-case: @MyApp.Counter@ → @my-app-counter@.
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

-- | Generate the class definition.
classDefinition :: String -> String -> Builder
classDefinition tagName jsModName =
  BB.stringUtf8 "class "
    <> BB.stringUtf8 (pascalFromKebab tagName)
    <> BB.stringUtf8 " extends HTMLElement {\n"
    <> constructorDef
    <> connectedCallback jsModName
    <> disconnectedCallback
    <> attributeChangedCallback
    <> observedAttributes
    <> BB.stringUtf8 "}\n"

-- | Generate constructor with Shadow DOM.
constructorDef :: Builder
constructorDef =
  BB.stringUtf8 "  constructor() {\n"
    <> BB.stringUtf8 "    super();\n"
    <> BB.stringUtf8 "    this._root = this.attachShadow({ mode: 'open' });\n"
    <> BB.stringUtf8 "    this._app = null;\n"
    <> BB.stringUtf8 "  }\n"

-- | Generate connectedCallback that initializes the Canopy app.
connectedCallback :: String -> Builder
connectedCallback jsModName =
  BB.stringUtf8 "  connectedCallback() {\n"
    <> BB.stringUtf8 "    var flags = {};\n"
    <> BB.stringUtf8 "    for (var attr of this.attributes) {\n"
    <> BB.stringUtf8 "      flags[attr.name] = attr.value;\n"
    <> BB.stringUtf8 "    }\n"
    <> BB.stringUtf8 "    var container = document.createElement('div');\n"
    <> BB.stringUtf8 "    this._root.appendChild(container);\n"
    <> BB.stringUtf8 "    this._app = "
    <> BB.stringUtf8 jsModName
    <> BB.stringUtf8 ".init({ node: container, flags: flags });\n"
    <> BB.stringUtf8 "  }\n"

-- | Generate disconnectedCallback for cleanup.
disconnectedCallback :: Builder
disconnectedCallback =
  BB.stringUtf8 "  disconnectedCallback() {\n"
    <> BB.stringUtf8 "    this._root.innerHTML = '';\n"
    <> BB.stringUtf8 "    this._app = null;\n"
    <> BB.stringUtf8 "  }\n"

-- | Generate attributeChangedCallback.
attributeChangedCallback :: Builder
attributeChangedCallback =
  BB.stringUtf8 "  attributeChangedCallback(name, oldValue, newValue) {\n"
    <> BB.stringUtf8 "    if (this._app && this._app.ports && this._app.ports.onAttributeChange) {\n"
    <> BB.stringUtf8 "      this._app.ports.onAttributeChange.send({ name: name, value: newValue });\n"
    <> BB.stringUtf8 "    }\n"
    <> BB.stringUtf8 "  }\n"

-- | Generate static observedAttributes getter.
observedAttributes :: Builder
observedAttributes =
  BB.stringUtf8 "  static get observedAttributes() { return []; }\n"

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
