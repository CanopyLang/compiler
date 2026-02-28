{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

-- | CLI command for generating Canopy FFI bindings from WebIDL specifications.
--
-- Provides the @canopy webidl@ command which parses WebIDL specification
-- files and generates type-safe Canopy modules with corresponding
-- JavaScript FFI runtime code.
--
-- == Usage
--
-- @
-- canopy webidl --output=src/Web/ specs/dom.webidl specs/fetch.webidl
-- @
--
-- This generates Canopy @.can@ modules and JavaScript kernel files
-- from the given WebIDL specifications.
--
-- @since 0.19.2
module WebIDL.Command
  ( -- * Command Interface
    Flags (..),
    run,
  )
where

import Control.Lens (makeLenses, (^.))
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import qualified Terminal.Print as Print
import qualified WebIDL
import qualified WebIDL.Config as Config

-- | Flags for the @canopy webidl@ command.
--
-- @since 0.19.2
data Flags = Flags
  { -- | Output directory for generated modules.
    _output :: !(Maybe String),
    -- | Whether to show verbose output.
    _verbose :: !Bool
  }
  deriving (Eq, Show)

makeLenses ''Flags

-- | Run the @canopy webidl@ command.
--
-- Parses the given WebIDL specification files and generates
-- Canopy modules and JavaScript kernel code.
--
-- @since 0.19.2
run :: [FilePath] -> Flags -> IO ()
run inputFiles flags =
  validateInputs inputFiles flags >>= either reportError (executeGeneration flags)

-- | Validate that input files exist and output directory is writable.
validateInputs :: [FilePath] -> Flags -> IO (Either String [FilePath])
validateInputs [] _ = pure (Left "No WebIDL input files specified.")
validateInputs paths _ = do
  missing <- filterMissing paths
  pure (checkMissing missing paths)

-- | Filter paths to those that do not exist.
filterMissing :: [FilePath] -> IO [FilePath]
filterMissing = fmap (map fst . filter (not . snd)) . traverse checkExists
  where
    checkExists p = (,) p <$> Dir.doesFileExist p

-- | Check if any files are missing and report an error if so.
checkMissing :: [FilePath] -> [FilePath] -> Either String [FilePath]
checkMissing [] paths = Right paths
checkMissing missing _ = Left ("Files not found: " ++ unwords missing)

-- | Execute WebIDL parsing and code generation.
executeGeneration :: Flags -> [FilePath] -> IO ()
executeGeneration flags paths = do
  reportParsingStart flags paths
  parseResult <- WebIDL.parseFiles paths
  either reportParseError (generateFromDefs flags) parseResult

-- | Parse and generate from definitions.
generateFromDefs :: Flags -> WebIDL.Definitions -> IO ()
generateFromDefs flags defs = do
  config <- buildConfig flags
  reportGenerating flags config
  WebIDL.generate config defs
  reportSuccess config

-- | Build the WebIDL configuration from flags.
buildConfig :: Flags -> IO Config.Config
buildConfig flags =
  pure (adjustOutputDir (flags ^. output) Config.defaultConfig)

-- | Adjust the output directory in the configuration.
--
-- Sets both the Canopy output and JavaScript output directories
-- to the given path.
adjustOutputDir :: Maybe String -> Config.Config -> Config.Config
adjustOutputDir Nothing config = config
adjustOutputDir (Just dir) config =
  config
    { Config.configOutput =
        (Config.configOutput config)
          { Config.outputCanopyDir = dir,
            Config.outputJsDir = dir
          }
    }

-- | Report that parsing has started (verbose mode).
reportParsingStart :: Flags -> [FilePath] -> IO ()
reportParsingStart flags paths
  | flags ^. verbose =
      Print.println [c|Parsing #{countStr} WebIDL file(s)...|]
  | otherwise = pure ()
  where
    countStr = show (length paths)

-- | Report that code generation is in progress (verbose mode).
reportGenerating :: Flags -> Config.Config -> IO ()
reportGenerating flags config
  | flags ^. verbose =
      Print.println [c|Generating Canopy modules to #{outDir}...|]
  | otherwise = pure ()
  where
    outDir = Config.outputCanopyDir (Config.configOutput config)

-- | Report a parse error to stderr.
reportError :: String -> IO ()
reportError msg =
  Print.printErrLn [c|{red|Error:} #{msg}|]

-- | Report a parse error from the WebIDL parser.
reportParseError :: String -> IO ()
reportParseError msg =
  Print.printErrLn [c|{red|WebIDL Parse Error:} #{msg}|]

-- | Report successful generation.
reportSuccess :: Config.Config -> IO ()
reportSuccess config =
  Print.println [c|{green|Success!} Generated Canopy bindings to #{outDir}|]
  where
    outDir = Config.outputCanopyDir (Config.configOutput config)
