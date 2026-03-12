{-# LANGUAGE OverloadedStrings #-}

-- | JavaScript wrapper generation for npm package consumption.
--
-- Generates thin JavaScript wrapper files that bridge npm packages
-- to Canopy's FFI system. Each wrapper:
--
--   * Imports the npm function by name
--   * Converts Canopy types to JS (unwraps newtypes, converts Maybe to null)
--   * Wraps Promise returns in Task/Cmd scheduler
--   * Handles callback-style APIs
--
-- Generated wrappers are @.ffi.js@ files placed alongside the Canopy source.
--
-- @since 0.20.1
module Generate.JavaScript.NpmWrapper
  ( -- * Wrapper Generation
    generateNpmWrapper
  , WrapperConfig (..)
  , ParamConversion (..)
  , ReturnConversion (..)
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.ByteString.Builder as BB

-- | Configuration for generating an npm wrapper function.
--
-- @since 0.20.1
data WrapperConfig = WrapperConfig
  { _wcPackageName :: !Text
  , _wcFunctionName :: !Text
  , _wcCanopyName :: !Text
  , _wcParams :: ![ParamConversion]
  , _wcReturn :: !ReturnConversion
  } deriving (Show, Eq)

-- | How to convert a Canopy parameter to a JS argument.
--
-- @since 0.20.1
data ParamConversion
  = PassThrough
    -- ^ No conversion needed (primitives).
  | UnwrapMaybe
    -- ^ Convert Maybe to nullable value.
  | UnwrapNewtype
    -- ^ Unwrap a single-field newtype.
  deriving (Show, Eq)

-- | How to convert a JS return value to a Canopy type.
--
-- @since 0.20.1
data ReturnConversion
  = ReturnDirect
    -- ^ Return as-is (primitives).
  | WrapPromise
    -- ^ Wrap Promise in Task scheduler.
  | WrapNullable
    -- ^ Wrap nullable in Maybe.
  | WrapCallback
    -- ^ Convert callback-style to Task.
  | ReturnCmd
    -- ^ Wrap void return in Cmd.
  deriving (Show, Eq)

-- | Generate a complete @.ffi.js@ wrapper file for an npm function.
--
-- @since 0.20.1
generateNpmWrapper :: WrapperConfig -> BB.Builder
generateNpmWrapper config =
  importLine <> "\n\n" <> functionDef
  where
    importLine = generateImport config
    functionDef = generateFunction config

-- | Generate the import statement.
generateImport :: WrapperConfig -> BB.Builder
generateImport config =
  "import { "
    <> textToBuilder (_wcFunctionName config)
    <> " } from '"
    <> textToBuilder (_wcPackageName config)
    <> "';\n"

-- | Generate the wrapper function definition.
generateFunction :: WrapperConfig -> BB.Builder
generateFunction config =
  jsdocAnnotation config
    <> "function "
    <> textToBuilder (_wcCanopyName config)
    <> "("
    <> paramList config
    <> ") {\n"
    <> functionBody config
    <> "}\n"

-- | Generate JSDoc annotation for the wrapper.
jsdocAnnotation :: WrapperConfig -> BB.Builder
jsdocAnnotation config =
  "/**\n * @canopy-ffi " <> textToBuilder (_wcCanopyName config) <> "\n */\n"

-- | Generate the parameter list.
paramList :: WrapperConfig -> BB.Builder
paramList config =
  mconcat (intersperse ", " (zipWith paramName [0 ..] (_wcParams config)))
  where
    paramName :: Int -> ParamConversion -> BB.Builder
    paramName i _ = "p" <> textToBuilder (Text.pack (show i))

-- | Generate the function body with appropriate conversions.
functionBody :: WrapperConfig -> BB.Builder
functionBody config =
  case _wcReturn config of
    ReturnDirect -> directBody config
    WrapPromise -> promiseBody config
    WrapNullable -> nullableBody config
    WrapCallback -> callbackBody config
    ReturnCmd -> cmdBody config

-- | Direct return without conversion.
directBody :: WrapperConfig -> BB.Builder
directBody config =
  "  return " <> callExpr config <> ";\n"

-- | Wrap a Promise return in Canopy's Task scheduler.
promiseBody :: WrapperConfig -> BB.Builder
promiseBody config =
  "  return _Scheduler_binding(function(callback) {\n"
    <> "    "
    <> callExpr config
    <> ".then(\n"
    <> "      function(value) { callback(_Scheduler_succeed(value)); },\n"
    <> "      function(error) { callback(_Scheduler_fail(error.message || String(error))); }\n"
    <> "    );\n"
    <> "  });\n"

-- | Wrap a nullable return in Maybe.
nullableBody :: WrapperConfig -> BB.Builder
nullableBody config =
  "  var result = " <> callExpr config <> ";\n"
    <> "  return result == null ? $canopy$core$Maybe$Nothing : $canopy$core$Maybe$Just(result);\n"

-- | Convert callback-style API to Task.
callbackBody :: WrapperConfig -> BB.Builder
callbackBody config =
  "  return _Scheduler_binding(function(callback) {\n"
    <> "    "
    <> callExprWithCallback config
    <> ";\n"
    <> "  });\n"

-- | Wrap void return in Cmd.
cmdBody :: WrapperConfig -> BB.Builder
cmdBody config =
  "  return _Platform_leaf('" <> textToBuilder (_wcCanopyName config) <> "', function() {\n"
    <> "    " <> callExpr config <> ";\n"
    <> "  });\n"

-- | Generate the npm function call expression with param conversions.
callExpr :: WrapperConfig -> BB.Builder
callExpr config =
  textToBuilder (_wcFunctionName config)
    <> "("
    <> mconcat (intersperse ", " (zipWith convertParam [0 ..] (_wcParams config)))
    <> ")"

-- | Generate call expression with callback parameter appended.
callExprWithCallback :: WrapperConfig -> BB.Builder
callExprWithCallback config =
  textToBuilder (_wcFunctionName config)
    <> "("
    <> mconcat (intersperse ", " (zipWith convertParam [0 ..] (_wcParams config)))
    <> (if null (_wcParams config) then "" else ", ")
    <> "function(err, result) {\n"
    <> "      if (err) { callback(_Scheduler_fail(err.message || String(err))); }\n"
    <> "      else { callback(_Scheduler_succeed(result)); }\n"
    <> "    })"

-- | Convert a single parameter based on its conversion type.
convertParam :: Int -> ParamConversion -> BB.Builder
convertParam i PassThrough = paramRef i
convertParam i UnwrapMaybe = paramRef i <> ".$" <> " === 'Just' ? " <> paramRef i <> ".a : null"
convertParam i UnwrapNewtype = paramRef i <> ".a"

-- | Reference to a parameter by index.
paramRef :: Int -> BB.Builder
paramRef i = "p" <> textToBuilder (Text.pack (show i))

-- | Helper: convert Text to Builder.
textToBuilder :: Text -> BB.Builder
textToBuilder = BB.byteString . Text.Encoding.encodeUtf8

-- | Intersperse a separator between builder elements.
intersperse :: BB.Builder -> [BB.Builder] -> [BB.Builder]
intersperse _ [] = []
intersperse _ [x] = [x]
intersperse sep (x : xs) = x : sep : intersperse sep xs
