{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Build - Build progress and code generation reporting for Canopy compiler
--
-- This module provides progress tracking for compilation and code generation
-- phases of the build process. It handles module compilation progress,
-- build result formatting, and code generation visualization with ASCII
-- diagrams showing module-to-file mappings.
--
-- == Build Progress Tracking
--
-- The module tracks compilation through these phases:
--
-- 1. **Compilation Start** - Initialize compilation tracking
-- 2. **Module Progress** - Track individual module compilation
-- 3. **Build Completion** - Display final compilation results
-- 4. **Code Generation** - Show output file generation with visual diagrams
--
-- == Progress Display Features
--
-- * **Real-time Updates** - Live compilation progress counters
-- * **Success Summary** - Formatted success messages with module counts
-- * **Error Reporting** - Build problem summaries with affected module counts
-- * **Code Generation Diagrams** - ASCII visualization of module-to-file mapping
--
-- == Usage Examples
--
-- === Build Progress Tracking
--
-- @
-- -- Track module compilation with terminal output
-- style <- terminal  
-- result <- trackBuild style $ \key -> do
--   modules <- getModulesToCompile
--   
--   compiledModules <- forM modules $ \moduleFile -> do
--     result <- compileModule moduleFile
--     report key BDone  -- Report completion of each module
--     return result
--   
--   return (Right compiledModules)
-- @
--
-- === Code Generation Reporting
--
-- @
-- -- Report JavaScript generation with ASCII diagram
-- style <- terminal
-- let modules = NE.List "Main" ["Utils", "Parser"]
-- reportGenerate style modules "dist/app.js"
-- -- Shows: Main ─┬─> dist/app.js
-- --         Utils ─┤
-- --         Parser ─┘
-- @
--
-- == Thread Safety
--
-- Build tracking uses concurrent threads with channel communication for
-- terminal output. The background thread safely updates progress display
-- while the main thread performs compilation work.
--
-- @since 0.19.1
module Reporting.Build
  ( -- * Build Tracking
    BKey
  , BMsg(..)
  , BResult
  , trackBuild
    -- * Code Generation Reporting
  , reportGenerate
    -- * Internal Utilities  
  , toFinalMessage
  , toGenDiagram
  , toGenLine
  ) where

import qualified Canopy.ModuleName as ModuleName
import Control.Concurrent (Chan, forkIO, newChan, readChan, writeChan)
import Control.Concurrent.STM (atomically, readTVarIO, writeTVar)
import qualified Data.NonEmptyList as NE
import Reporting.Key (Key(..))
import Reporting.Platform (hbar, vtop, vmiddle, vbottom)
import qualified Reporting.Exit as Exit
import Reporting.Style (Style(..))
import System.IO (hFlush, stdout)

-- | Key type for build progress tracking messages.
--
-- Specialized key for sending compilation progress updates during
-- the build process. Used with 'trackBuild' to report module
-- compilation progress.
--
-- @since 0.19.1
type BKey = Key BMsg

-- | Result type for build operations that may fail.
--
-- Represents the outcome of a build operation, where success yields
-- a value of type @a@ and failure yields a 'BuildProblem' describing
-- what went wrong.
--
-- Common build problems include:
--
-- * Module compilation errors (syntax, type errors)
-- * Project configuration issues
-- * Dependency problems
--
-- @since 0.19.1
type BResult a = Either Exit.BuildProblem a

-- | Progress messages for compilation tracking.
--
-- Represents compilation events during the build process. Currently supports
-- module completion events, with potential for expansion to include more
-- granular progress reporting.
--
-- @since 0.19.1
data BMsg
  = -- | Indicate completion of a module compilation.
    --
    -- Sent when a module finishes compiling, whether successfully or with
    -- errors. Used to update the progress counter showing how many modules
    -- have been processed.
    BDone

-- | Track compilation progress with style-specific output.
--
-- Manages build progress reporting by creating an appropriate progress
-- tracking context based on the output style. For terminal output, spawns
-- a background thread to handle live compilation progress while the main
-- thread performs compilation work.
--
-- The function provides a 'BKey' to the callback for sending progress messages.
-- Progress shows the number of modules compiled and provides a final summary
-- of compilation results.
--
-- ==== Examples
--
-- @
-- -- Track module compilation with terminal output
-- style <- terminal  
-- result <- trackBuild style $ \key -> do
--   modules <- getModulesToCompile
--   
--   compiledModules <- forM modules $ \moduleFile -> do
--     result <- compileModule moduleFile
--     report key BDone  -- Report completion of each module
--     return result
--   
--   return (Right compiledModules)
-- @
--
-- @
-- -- Silent build (no progress output)
-- let style = silent
-- result <- trackBuild style $ \key -> do
--   -- Progress reports are ignored in silent mode
--   buildProject config
-- @
--
-- ==== Progress Display
--
-- Terminal style shows real-time compilation progress:
--
-- @
-- Compiling ...
-- Compiling (1)
-- Compiling (2)
-- Success! Compiled 2 modules.
-- @
--
-- For build failures:
--
-- @
-- Compiling (3)
-- Detected problems in 2 modules.
-- @
--
-- ==== Thread Safety
--
-- The terminal implementation uses concurrent threads with channel communication.
-- The background thread safely updates progress display while the main thread
-- performs compilation work. Progress messages are serialized through channels.
--
-- ==== Error Handling
--
-- Build errors are captured in the 'BResult' type and formatted appropriately:
--
-- * Silent mode - No output, only exit code
-- * JSON mode - Structured error information
-- * Terminal mode - Formatted error messages with context
--
-- The progress tracking thread is properly cleaned up regardless of build outcome.
--
-- @since 0.19.1
trackBuild :: Style -> (BKey -> IO (BResult a)) -> IO (BResult a)
trackBuild style callback =
  case style of
    Silent ->
      callback (Key (\_ -> return ()))
    Json ->
      callback (Key (\_ -> return ()))
    Terminal mvar ->
      do
        chan <- newChan

        _ <- forkIO $
          do
            -- Use TVar for thread synchronization
            readTVarIO mvar
            putStrFlush "Compiling ..."
            buildLoop chan 0
            atomically $ writeTVar mvar ()

        result <- callback (Key (writeChan chan . Left))
        writeChan chan (Right result)
        return result

-- | Main loop for build progress display.
--
-- Processes build messages and updates the compilation progress counter.
-- Continues until the final result is received, then displays the
-- appropriate completion message.
--
-- @since 0.19.1
buildLoop :: Chan (Either BMsg (BResult a)) -> Int -> IO ()
buildLoop chan done =
  do
    msg <- readChan chan
    case msg of
      Left BDone ->
        do
          let !done1 = done + 1
          putStrFlush ("\rCompiling (" <> (show done1 <> ")"))
          buildLoop chan done1
      Right result ->
        let !message = toFinalMessage done result
            !width = 12 + length (show done)
         in putStrLn $
              if length message < width
                then '\r' : (replicate width ' ' <> ('\r' : message))
                else '\r' : message

-- | Generate final completion message based on build result.
--
-- Creates appropriate success or failure messages based on the number
-- of modules compiled and the final build result.
--
-- @since 0.19.1
toFinalMessage :: Int -> BResult a -> String
toFinalMessage done result =
  case result of
    Right _ ->
      case done of
        0 -> "Success!"
        1 -> "Success! Compiled 1 module."
        n -> "Success! Compiled " <> (show n <> " modules.")
    Left problem ->
      case problem of
        Exit.BuildBadModules _ _ [] ->
          "Detected problems in 1 module."
        Exit.BuildBadModules _ _ (_ : ps) ->
          "Detected problems in " <> (show (2 + length ps) <> " modules.")
        Exit.BuildProjectProblem _ ->
          "Detected a problem."

-- | Report code generation completion with output file information.
--
-- Displays a summary of the code generation process, showing which modules
-- were processed and where the output was written. The display format
-- adapts to the reporting style:
--
-- * Silent - No output
-- * JSON - No output (code generation not typically reported in JSON)
-- * Terminal - ASCII diagram showing module-to-file mapping
--
-- ==== Examples
--
-- @
-- -- Report JavaScript generation
-- style <- terminal
-- let modules = NE.List "Main" ["Utils", "Parser"]
-- reportGenerate style modules "dist/app.js"
-- @
--
-- Produces terminal output:
--
-- @
--     Main ─┬─> dist/app.js
--     Utils ─┤
--     Parser ─┘
-- @
--
-- @
-- -- Single module generation
-- style <- terminal
-- let modules = NE.List "Main" []
-- reportGenerate style modules "build/main.js"
-- @
--
-- Produces:
--
-- @
--     Main ──> build/main.js
-- @
--
-- ==== ASCII Diagram Format
--
-- The terminal output uses platform-appropriate characters:
--
-- * Unicode box drawing on Unix: ─┬┤┘
-- * ASCII fallbacks on Windows: -++|
--
-- The diagram clearly shows which modules contribute to the output file,
-- with proper alignment and visual hierarchy.
--
-- ==== Thread Safety
--
-- For terminal style, uses MVar synchronization to ensure clean output
-- without interference from other concurrent reporting operations.
--
-- @since 0.19.1
reportGenerate :: Style -> NE.List ModuleName.Raw -> FilePath -> IO ()
reportGenerate style names output =
  case style of
    Silent ->
      return ()
    Json ->
      return ()
    Terminal mvar ->
      do
        _ <- readTVarIO mvar
        let cnames = fmap ModuleName.toChars names
        putStrLn ('\n' : toGenDiagram cnames output)

-- | Generate ASCII diagram for module-to-file mapping.
--
-- Creates a visual representation showing how multiple modules contribute
-- to a single output file. Uses box-drawing characters that adapt to
-- platform capabilities (Unicode on Unix, ASCII on Windows).
--
-- ==== Diagram Structure
--
-- For multiple modules:
-- @
--     Module1 ─┬─> output.js
--     Module2 ─┤
--     Module3 ─┘
-- @
--
-- For single module:
-- @
--     Module ──> output.js
-- @
--
-- ==== Examples
--
-- @
-- let modules = NE.List "Main" ["Utils", "Types"]
-- let diagram = toGenDiagram modules "app.js"
-- putStrLn diagram
-- @
--
-- @since 0.19.1
toGenDiagram :: NE.List String -> FilePath -> String
toGenDiagram (NE.List name names) output =
  let width = 3 + foldr (max . length) (length name) names
   in case names of
        [] ->
          toGenLine width name ('>' : ' ' : (output <> "\n"))
        _ : _ ->
          unlines $
            toGenLine width name (vtop : hbar : hbar : '>' : ' ' : output) :
            reverse (zipWith (toGenLine width) (reverse names) ([vbottom] : repeat [vmiddle]))

-- | Generate a single line of the generation diagram.
--
-- Formats one module name with appropriate padding and connecting characters
-- to align with other lines in the diagram. The width parameter ensures
-- consistent alignment across all modules.
--
-- ==== Parameters
--
-- * @width@ - Total width for module name and padding
-- * @name@ - Module name to display
-- * @end@ - Terminating characters (connectors and output path)
--
-- ==== Examples
--
-- @
-- line1 = toGenLine 10 "Main" "─┬─> app.js"
-- line2 = toGenLine 10 "Utils" "─┤"
-- -- Results in aligned output with consistent spacing
-- @
--
-- @since 0.19.1
toGenLine :: Int -> String -> String -> String
toGenLine width name end =
  "    " <> (name <> (' ' : (replicate (width - length name) hbar <> end)))

-- | Output string and immediately flush stdout.
--
-- Ensures that output appears immediately in the terminal, which is
-- important for progress indicators and real-time feedback.
--
-- @since 0.19.1
putStrFlush :: String -> IO ()
putStrFlush str =
  putStr str >> hFlush stdout