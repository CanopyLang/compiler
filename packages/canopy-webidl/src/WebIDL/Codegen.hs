{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | WebIDL Code Generation
--
-- Main module for generating Canopy source code and JavaScript
-- runtime from transformed WebIDL definitions.
--
-- @since 0.20.0
module WebIDL.Codegen
  ( -- * High-level generation
    generateCanopyModules
  , generateJavaScriptKernel

    -- * Module utilities
  , moduleToFilePath
  , createDirectories
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)

import WebIDL.AST
import WebIDL.Config
import WebIDL.Transform
import qualified WebIDL.Codegen.Canopy as Canopy
import qualified WebIDL.Codegen.JavaScript as JavaScript


-- | Generate Canopy source modules from definitions
generateCanopyModules :: Config -> Definitions -> IO ()
generateCanopyModules config defs = do
  let modules = transformDefinitions config defs
  mapM_ (writeCanopyModule config) modules


-- | Generate JavaScript kernel code from definitions
generateJavaScriptKernel :: Config -> Definitions -> IO ()
generateJavaScriptKernel config defs = do
  let modules = transformDefinitions config defs
  mapM_ (writeJavaScriptModule config) modules


-- | Write a single Canopy module to disk
writeCanopyModule :: Config -> CanopyModule -> IO ()
writeCanopyModule config canopyMod = do
  let outDir = outputCanopyDir (configOutput config)
      filePath = outDir </> moduleToFilePath (cmName canopyMod) ".can"
      content = Canopy.renderModule config canopyMod

  createDirectoryIfMissing True (takeDirectory filePath)
  TIO.writeFile filePath content


-- | Write a single JavaScript module to disk
writeJavaScriptModule :: Config -> CanopyModule -> IO ()
writeJavaScriptModule config canopyMod = do
  let outDir = outputJsDir (configOutput config)
      kernelPrefix = outputKernelPrefix (configOutput config)
      moduleName = kernelPrefix <> "." <> cmName canopyMod
      filePath = outDir </> moduleToFilePath moduleName ".js"
      content = JavaScript.renderModule config canopyMod

  createDirectoryIfMissing True (takeDirectory filePath)
  TIO.writeFile filePath content


-- | Convert a module name to a file path
moduleToFilePath :: Text -> String -> FilePath
moduleToFilePath moduleName ext =
  Text.unpack (Text.replace "." "/" moduleName) <> ext


-- | Create all necessary directories for output
createDirectories :: Config -> IO ()
createDirectories config = do
  createDirectoryIfMissing True (outputCanopyDir (configOutput config))
  createDirectoryIfMissing True (outputJsDir (configOutput config))
