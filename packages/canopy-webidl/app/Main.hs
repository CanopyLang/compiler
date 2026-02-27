{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | WebIDL Generator CLI
--
-- Command-line interface for generating Canopy FFI bindings
-- from WebIDL specification files.
--
-- Usage:
--   canopy-webidl-gen [OPTIONS] <webidl-files>...
--
-- @since 0.20.0
module Main where

import Control.Monad (when)
import Data.Text (Text)
import Options.Applicative
import System.Directory (doesFileExist)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

import qualified WebIDL
import WebIDL.Config (Config(..), OutputConfig(..), PackageConfig(..))
import qualified WebIDL.Config as Config


-- | CLI options
data Options = Options
  { optConfigFile :: !(Maybe FilePath)
  , optOutputDir :: !(Maybe FilePath)
  , optJsOutputDir :: !(Maybe FilePath)
  , optModulePrefix :: !(Maybe Text)
  , optPackageName :: !(Maybe Text)
  , optVerbose :: !Bool
  , optDryRun :: !Bool
  , optInputFiles :: ![FilePath]
  } deriving (Eq, Show)


-- | Parse CLI options
optionsParser :: Parser Options
optionsParser = Options
  <$> optional (strOption
      ( long "config"
     <> short 'c'
     <> metavar "FILE"
     <> help "Configuration file (JSON)" ))
  <*> optional (strOption
      ( long "output"
     <> short 'o'
     <> metavar "DIR"
     <> help "Output directory for .can files" ))
  <*> optional (strOption
      ( long "js-output"
     <> short 'j'
     <> metavar "DIR"
     <> help "Output directory for .js files" ))
  <*> optional (strOption
      ( long "module-prefix"
     <> short 'm'
     <> metavar "PREFIX"
     <> help "Module prefix (e.g., Dom)" ))
  <*> optional (strOption
      ( long "package"
     <> short 'p'
     <> metavar "NAME"
     <> help "Package name (e.g., canopy/dom)" ))
  <*> switch
      ( long "verbose"
     <> short 'v'
     <> help "Verbose output" )
  <*> switch
      ( long "dry-run"
     <> short 'n'
     <> help "Parse only, don't generate files" )
  <*> some (argument str
      ( metavar "FILES..."
     <> help "WebIDL specification files" ))


-- | Program description
programInfo :: ParserInfo Options
programInfo = info (optionsParser <**> helper)
  ( fullDesc
 <> progDesc "Generate Canopy FFI bindings from WebIDL specifications"
 <> header "canopy-webidl-gen - WebIDL to Canopy FFI generator" )


-- | Main entry point
main :: IO ()
main = do
  opts <- execParser programInfo
  config <- loadConfiguration opts
  runGenerator opts config


-- | Load configuration from file or defaults
loadConfiguration :: Options -> IO Config
loadConfiguration opts = do
  baseConfig <- loadBaseConfig (optConfigFile opts)
  pure (applyOverrides opts baseConfig)


-- | Load base configuration
loadBaseConfig :: Maybe FilePath -> IO Config
loadBaseConfig Nothing = pure Config.defaultConfig
loadBaseConfig (Just path) = do
  exists <- doesFileExist path
  if exists
    then do
      result <- Config.loadConfig path
      case result of
        Left err -> do
          hPutStrLn stderr ("Error loading config: " <> err)
          exitFailure
        Right cfg -> pure cfg
    else do
      hPutStrLn stderr ("Config file not found: " <> path)
      exitFailure


-- | Apply CLI overrides to configuration
applyOverrides :: Options -> Config -> Config
applyOverrides opts config = config
  { configPackage = applyPackageOverrides opts (configPackage config)
  , configOutput = applyOutputOverrides opts (configOutput config)
  }


-- | Apply package overrides
applyPackageOverrides :: Options -> PackageConfig -> PackageConfig
applyPackageOverrides opts pkg = pkg
  { pkgName = maybe (pkgName pkg) id (optPackageName opts)
  , pkgModulePrefix = maybe (pkgModulePrefix pkg) id (optModulePrefix opts)
  }


-- | Apply output overrides
applyOutputOverrides :: Options -> OutputConfig -> OutputConfig
applyOutputOverrides opts out = out
  { outputCanopyDir = maybe (outputCanopyDir out) id (optOutputDir opts)
  , outputJsDir = maybe (outputJsDir out) id (optJsOutputDir opts)
  }


-- | Run the generator
runGenerator :: Options -> Config -> IO ()
runGenerator opts config = do
  when (optVerbose opts) $ do
    putStrLn "WebIDL Generator"
    putStrLn "================"
    putStrLn ("Input files: " <> show (optInputFiles opts))
    putStrLn ("Output dir: " <> outputCanopyDir (configOutput config))
    putStrLn ("JS output: " <> outputJsDir (configOutput config))
    putStrLn ""

  result <- WebIDL.parseFiles (optInputFiles opts)
  case result of
    Left err -> do
      hPutStrLn stderr "Parse error:"
      hPutStrLn stderr err
      exitFailure
    Right defs -> do
      when (optVerbose opts) $ do
        putStrLn ("Parsed " <> show (length defs) <> " definitions")
        putStrLn ""

      if optDryRun opts
        then do
          putStrLn "Dry run - no files generated"
          exitSuccess
        else do
          when (optVerbose opts) $
            putStrLn "Generating Canopy modules..."
          WebIDL.generateCanopy config defs

          when (optVerbose opts) $
            putStrLn "Generating JavaScript runtime..."
          WebIDL.generateJavaScript config defs

          when (optVerbose opts) $
            putStrLn "Done!"
          exitSuccess
