{-# LANGUAGE OverloadedStrings #-}

-- | End-to-end npm FFI pipeline.
--
-- Chains the individual FFI subsystems into a single pipeline that
-- resolves an npm package, parses its @.d.ts@ declarations, validates
-- types against Canopy FFI annotations, and generates a JavaScript
-- wrapper file:
--
-- @
-- resolveNpmModule -> parseDtsFile -> validateFFI -> generateNpmWrapper
-- @
--
-- This module is the integration glue that wires the orphaned modules
-- into a callable pipeline.
--
-- @since 0.20.1
module FFI.NpmPipeline
  ( -- * Pipeline
    runNpmPipeline
  , NpmPipelineResult (..)
  , NpmPipelineError (..)

    -- * Type Mapping
  , tsTypeToParamConversion
  , tsTypeToReturnConversion
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.ByteString.Builder as BB
import qualified Canopy.Data.Name as Name
import FFI.Resolve (NpmResolution (..))
import qualified FFI.Resolve as Resolve
import Generate.JavaScript.NpmWrapper (ParamConversion (..), ReturnConversion (..), WrapperConfig (..))
import qualified Generate.JavaScript.NpmWrapper as NpmWrapper
import Generate.TypeScript.Parser (DtsExport (..))
import qualified Generate.TypeScript.Parser as DtsParser
import Generate.TypeScript.Types (TsType (..))

-- | Result of a successful npm pipeline run.
--
-- @since 0.20.1
data NpmPipelineResult = NpmPipelineResult
  { _nprWrapper :: !BB.Builder
    -- ^ Generated JavaScript wrapper content.
  , _nprWarnings :: ![Text]
    -- ^ Type validation warnings (non-fatal).
  } deriving (Show)

-- | Errors during the npm pipeline.
--
-- @since 0.20.1
data NpmPipelineError
  = NpmNotFound !Text
    -- ^ Package not found in node_modules.
  | NpmNoDts !Text
    -- ^ No @.d.ts@ file found for the package.
  | NpmParseFailed !Text !String
    -- ^ Failed to parse the @.d.ts@ file.
  | NpmNoExport !Text !Text
    -- ^ The requested function was not found in exports.
  deriving (Show, Eq)

-- | Run the full npm FFI pipeline for a single function.
--
-- Given a package name, function name, and Canopy-side name, resolves
-- the npm package, parses its type declarations, maps TypeScript types
-- to Canopy FFI conversions, and generates a wrapper.
--
-- @since 0.20.1
runNpmPipeline
  :: Text
  -- ^ npm package name
  -> Text
  -- ^ Function name to import
  -> Text
  -- ^ Canopy-side function name
  -> FilePath
  -- ^ Project directory
  -> IO (Either NpmPipelineError NpmPipelineResult)
runNpmPipeline packageName funcName canopyName projectDir = do
  resolution <- Resolve.resolveNpmModule packageName projectDir
  case resolution of
    Nothing -> pure (Left (NpmNotFound packageName))
    Just npmRes -> processResolution packageName funcName canopyName npmRes

-- | Process a resolved npm package through the pipeline.
processResolution
  :: Text -> Text -> Text -> NpmResolution
  -> IO (Either NpmPipelineError NpmPipelineResult)
processResolution packageName funcName canopyName npmRes = do
  let dtsPath = _npmDtsPath npmRes
  dtsContent <- readFile dtsPath
  pure (buildWrapper packageName funcName canopyName dtsPath dtsContent)

-- | Parse the @.d.ts@ file and generate the wrapper.
buildWrapper
  :: Text -> Text -> Text -> FilePath -> String
  -> Either NpmPipelineError NpmPipelineResult
buildWrapper packageName funcName canopyName dtsPath dtsContent =
  case DtsParser.parseDtsFile dtsPath dtsContent of
    Left err -> Left (NpmParseFailed packageName err)
    Right exports -> buildFromExports packageName funcName canopyName exports

-- | Find the target export and generate a wrapper config.
buildFromExports
  :: Text -> Text -> Text -> [DtsExport]
  -> Either NpmPipelineError NpmPipelineResult
buildFromExports packageName funcName canopyName exports =
  case findExport funcName exports of
    Nothing -> Left (NpmNoExport packageName funcName)
    Just (paramTypes, retType) ->
      Right (generateResult packageName funcName canopyName paramTypes retType)

-- | Find a function or const export by name.
findExport :: Text -> [DtsExport] -> Maybe ([TsType], TsType)
findExport target = foldr checkExport Nothing
  where
    checkExport (DtsExportFunction name params ret) acc
      | nameMatches target name = Just (params, ret)
      | otherwise = acc
    checkExport (DtsExportConst name tsType) acc
      | nameMatches target name = Just ([], tsType)
      | otherwise = acc
    checkExport _ acc = acc

    nameMatches t n = Text.pack (Name.toChars n) == t

-- | Generate the pipeline result from resolved types.
generateResult
  :: Text -> Text -> Text -> [TsType] -> TsType
  -> NpmPipelineResult
generateResult packageName funcName canopyName paramTypes retType =
  NpmPipelineResult
    { _nprWrapper = NpmWrapper.generateNpmWrapper config
    , _nprWarnings = []
    }
  where
    config = WrapperConfig
      { _wcPackageName = packageName
      , _wcFunctionName = funcName
      , _wcCanopyName = canopyName
      , _wcParams = fmap tsTypeToParamConversion paramTypes
      , _wcReturn = tsTypeToReturnConversion retType
      }

-- | Map a TypeScript parameter type to a Canopy FFI param conversion.
--
-- @since 0.20.1
tsTypeToParamConversion :: TsType -> ParamConversion
tsTypeToParamConversion (TsUnion _) = UnwrapMaybe
tsTypeToParamConversion (TsObject _) = UnwrapNewtype
tsTypeToParamConversion (TsFunction _ _) = ConvertCallback
tsTypeToParamConversion _ = PassThrough

-- | Map a TypeScript return type to a Canopy FFI return conversion.
--
-- @since 0.20.1
tsTypeToReturnConversion :: TsType -> ReturnConversion
tsTypeToReturnConversion (TsNamed name _)
  | Name.toChars name == "Promise" = WrapPromise
  | otherwise = ReturnDirect
tsTypeToReturnConversion TsVoid = ReturnCmd
tsTypeToReturnConversion (TsUnion _) = WrapNullable
tsTypeToReturnConversion _ = ReturnDirect
