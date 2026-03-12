{-# LANGUAGE OverloadedStrings #-}

-- | Web Component interface introspection.
--
-- Extracts flag attributes and port events from Canopy module metadata
-- to generate typed Web Components with proper attribute coercion and
-- event dispatching.
--
-- Flag fields are mapped to observed HTML attributes with type-appropriate
-- coercion (e.g. @Int@ fields use @parseInt@, @Bool@ fields use presence
-- checking). Outgoing ports are mapped to @CustomEvent@ dispatches.
--
-- @since 0.20.1
module Generate.JavaScript.WebComponent.Introspect
  ( extractFlagAttrs
  , extractPortEvents
  , canopyTypeToCoercion
  ) where

import Generate.JavaScript.WebComponent (AttrCoercion (..), FlagAttr (..), PortEvent (..))
import qualified Generate.JavaScript.WebComponent as WebComponent

-- | Extract flag attributes from a list of (fieldName, typeName) pairs.
--
-- Each field in the Flags record becomes an observed HTML attribute
-- with appropriate type coercion. Field names are converted from
-- camelCase to kebab-case for the HTML attribute name.
--
-- ==== Examples
--
-- >>> extractFlagAttrs [("initialCount", "Int")]
-- [FlagAttr {_faFieldName = "initialCount", _faAttrName = "initial-count", _faCoercion = CoerceInt}]
--
-- @since 0.20.1
extractFlagAttrs :: [(String, String)] -> [FlagAttr]
extractFlagAttrs = map toFlagAttr
  where
    toFlagAttr (name, typeName) = FlagAttr
      { _faFieldName = name
      , _faAttrName = WebComponent.camelToKebab name
      , _faCoercion = canopyTypeToCoercion typeName
      }

-- | Extract port events from a list of (portName, direction) pairs.
--
-- Only outgoing ports (with direction @"outgoing"@) become CustomEvents.
-- Incoming ports are filtered out since they receive data rather than
-- emit it.
--
-- ==== Examples
--
-- >>> extractPortEvents [("onResult", "outgoing"), ("setInput", "incoming")]
-- [PortEvent {_pePortName = "onResult", _peEventName = "on-result"}]
--
-- @since 0.20.1
extractPortEvents :: [(String, String)] -> [PortEvent]
extractPortEvents = concatMap toPortEvent
  where
    toPortEvent (name, "outgoing") = [PortEvent
      { _pePortName = name
      , _peEventName = WebComponent.camelToKebab name
      }]
    toPortEvent _ = []

-- | Map a Canopy type name to the appropriate HTML attribute coercion.
--
-- Recognized types:
--
--   * @"Int"@ -> 'CoerceInt' (uses @parseInt@)
--   * @"Float"@ -> 'CoerceFloat' (uses @parseFloat@)
--   * @"Bool"@ -> 'CoerceBool' (uses presence check)
--   * Everything else -> 'CoerceString' (pass-through)
--
-- @since 0.20.1
canopyTypeToCoercion :: String -> AttrCoercion
canopyTypeToCoercion "Int" = CoerceInt
canopyTypeToCoercion "Float" = CoerceFloat
canopyTypeToCoercion "Bool" = CoerceBool
canopyTypeToCoercion _ = CoerceString
