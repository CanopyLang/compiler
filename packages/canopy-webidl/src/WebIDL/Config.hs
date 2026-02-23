{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | WebIDL Generator Configuration
--
-- Configuration options for controlling how WebIDL specifications
-- are transformed into Canopy modules and JavaScript runtime code.
--
-- @since 0.20.0
module WebIDL.Config
  ( -- * Configuration types
    Config(..)
  , PackageConfig(..)
  , TypeMapping(..)
  , OutputConfig(..)

    -- * Default configurations
  , defaultConfig
  , defaultPackageConfig
  , defaultTypeMapping
  , defaultOutputConfig

    -- * Configuration loading
  , loadConfig
  , parseConfig
  ) where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text.Encoding as Text.Encoding
import GHC.Generics (Generic)


-- | Main configuration for WebIDL code generation
data Config = Config
  { configPackage :: !PackageConfig
    -- ^ Package metadata and structure
  , configTypeMapping :: !TypeMapping
    -- ^ Custom type mappings
  , configOutput :: !OutputConfig
    -- ^ Output settings
  , configIncludeSpecs :: ![FilePath]
    -- ^ WebIDL specification files to include
  , configExcludeInterfaces :: ![Text]
    -- ^ Interfaces to exclude from generation
  , configIncludeInterfaces :: !(Maybe [Text])
    -- ^ If set, only include these interfaces (whitelist)
  } deriving (Eq, Show, Generic)

instance FromJSON Config
instance ToJSON Config


-- | Package configuration
data PackageConfig = PackageConfig
  { pkgName :: !Text
    -- ^ Package name (e.g., "canopy/dom")
  , pkgVersion :: !Text
    -- ^ Package version
  , pkgSummary :: !Text
    -- ^ Package summary description
  , pkgModulePrefix :: !Text
    -- ^ Module prefix (e.g., "Dom" becomes "Dom.Element", "Dom.Node")
  , pkgExposedModules :: !(Maybe [Text])
    -- ^ If set, only expose these modules
  } deriving (Eq, Show, Generic)

instance FromJSON PackageConfig
instance ToJSON PackageConfig


-- | Type mapping configuration for WebIDL to Canopy conversion
data TypeMapping = TypeMapping
  { mapPrimitives :: !(Map Text Text)
    -- ^ Primitive type mappings (e.g., "unsigned long" -> "Int")
  , mapInterfaces :: !(Map Text Text)
    -- ^ Interface type mappings (e.g., "HTMLElement" -> "Element")
  , mapPromise :: !Text
    -- ^ Task type name for Promise conversion
  , mapNullable :: !Text
    -- ^ Maybe type name for nullable conversion
  , mapSequence :: !Text
    -- ^ List type name for sequence conversion
  , mapRecord :: !Text
    -- ^ Dict type name for record conversion
  } deriving (Eq, Show, Generic)

instance FromJSON TypeMapping
instance ToJSON TypeMapping


-- | Output configuration
data OutputConfig = OutputConfig
  { outputCanopyDir :: !FilePath
    -- ^ Directory for generated .can files
  , outputJsDir :: !FilePath
    -- ^ Directory for generated kernel .js files
  , outputKernelPrefix :: !Text
    -- ^ Kernel module prefix (e.g., "Canopy.Kernel")
  , outputGenerateTests :: !Bool
    -- ^ Whether to generate test modules
  , outputIncludeComments :: !Bool
    -- ^ Include documentation comments in output
  } deriving (Eq, Show, Generic)

instance FromJSON OutputConfig
instance ToJSON OutputConfig


-- | Default configuration for WebIDL generation
defaultConfig :: Config
defaultConfig = Config
  { configPackage = defaultPackageConfig
  , configTypeMapping = defaultTypeMapping
  , configOutput = defaultOutputConfig
  , configIncludeSpecs = []
  , configExcludeInterfaces = []
  , configIncludeInterfaces = Nothing
  }


-- | Default package configuration
defaultPackageConfig :: PackageConfig
defaultPackageConfig = PackageConfig
  { pkgName = "canopy/web-api"
  , pkgVersion = "1.0.0"
  , pkgSummary = "Generated WebIDL bindings for Canopy"
  , pkgModulePrefix = "WebAPI"
  , pkgExposedModules = Nothing
  }


-- | Default type mapping following Canopy conventions
defaultTypeMapping :: TypeMapping
defaultTypeMapping = TypeMapping
  { mapPrimitives = Map.fromList
      [ ("boolean", "Bool")
      , ("byte", "Int")
      , ("octet", "Int")
      , ("short", "Int")
      , ("unsigned short", "Int")
      , ("long", "Int")
      , ("unsigned long", "Int")
      , ("long long", "Int")
      , ("unsigned long long", "Int")
      , ("float", "Float")
      , ("unrestricted float", "Float")
      , ("double", "Float")
      , ("unrestricted double", "Float")
      , ("bigint", "Int")
      , ("DOMString", "String")
      , ("ByteString", "String")
      , ("USVString", "String")
      , ("any", "Value")
      , ("void", "()")
      , ("undefined", "()")
      , ("object", "Value")
      ]
  , mapInterfaces = Map.empty
  , mapPromise = "Task"
  , mapNullable = "Maybe"
  , mapSequence = "List"
  , mapRecord = "Dict"
  }


-- | Default output configuration
defaultOutputConfig :: OutputConfig
defaultOutputConfig = OutputConfig
  { outputCanopyDir = "src"
  , outputJsDir = "src"
  , outputKernelPrefix = "Canopy.Kernel"
  , outputGenerateTests = True
  , outputIncludeComments = True
  }


-- | Load configuration from a JSON file
loadConfig :: FilePath -> IO (Either String Config)
loadConfig path = do
  contents <- LBS.readFile path
  pure (Aeson.eitherDecode contents)


-- | Parse configuration from JSON text
parseConfig :: Text -> Either String Config
parseConfig txt =
  Aeson.eitherDecode (LBS.fromStrict (Text.Encoding.encodeUtf8 txt))
