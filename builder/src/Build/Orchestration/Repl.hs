{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | REPL-specific build orchestration for the Canopy compiler.
--
-- This module provides specialized build coordination for REPL interactions,
-- handling the unique requirements of interactive development including fast
-- iteration, dependency resolution, and artifact generation optimized for
-- REPL usage.
--
-- === Primary Responsibilities
--
-- * REPL build orchestration ('fromRepl')
-- * REPL module processing and compilation
-- * REPL-specific dependency crawling
-- * Interactive development artifact generation
-- * Fast iteration support for REPL environment
--
-- === Usage Examples
--
-- @
-- -- Build for REPL interaction
-- result <- fromRepl root details sourceCode
-- case result of
--   Left replError -> handleReplError replError
--   Right artifacts -> useReplArtifacts artifacts
--
-- -- Process parsed REPL module
-- artifacts <- processReplModule env root details source module
-- @
--
-- === REPL Build Process
--
-- The REPL build process is optimized for speed and follows these steps:
--
-- 1. Parse the input source code
-- 2. Crawl dependencies of the REPL module
-- 3. Check project integrity and load interfaces
-- 4. Compile the module with fresh dependencies
-- 5. Generate REPL-specific artifacts
--
-- === Performance Optimizations
--
-- REPL builds are optimized for fast iteration:
--
-- * Minimal dependency crawling (only imported modules)
-- * Incremental compilation where possible
-- * Cached interface loading
-- * Streamlined artifact generation
--
-- @since 0.19.1
module Build.Orchestration.Repl
  ( -- * REPL Build Functions
    fromRepl
  , processReplModule
  , compileReplModule
    
  -- * REPL Dependency Management
  , crawlReplDependencies
  ) where

-- Canopy-specific imports
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline

-- Build system modules
import Build.Config (CheckConfig (..), DepsConfig (..))
import qualified Build.Crawl as Crawl
import qualified Build.Dependencies as Dependencies
import qualified Build.Module.Check as Check
import Build.Types
  ( Env (..)
  , AbsoluteSrcDir (..)
  , Status (..)
  , Dependencies
  , ReplArtifacts (..)
  )
import qualified Build.Validation as Validation

-- Parser and AST imports  
import qualified AST.Source as Src
import qualified Parse.Module as Parse

-- Standard library imports
import Control.Concurrent.MVar
  ( MVar
  , readMVar
  , newEmptyMVar
  , newMVar
  , putMVar
  )
import qualified Control.Concurrent as Control.Concurrent
import qualified Data.ByteString as B
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.NonEmptyList as NE
import qualified Reporting
import qualified Reporting.Error as Error
import qualified Reporting.Exit as Exit
import qualified System.Directory as Dir
import System.FilePath ((</>))

-- =============================================================================
-- Project Validation Functions  
-- =============================================================================
-- Local implementation to avoid circular imports between Build.Orchestration
-- and Build.Orchestration.Repl modules.

-- | Check project integrity at the midpoint of the build.
--
-- Local implementation to avoid circular imports between Build.Orchestration
-- and Build.Orchestration.Repl modules.
checkMidpoint :: MVar (Maybe Dependencies) -> Map ModuleName.Raw Status -> IO (Either Exit.BuildProjectProblem Dependencies)
checkMidpoint dmvar statuses =
  case Validation.checkForCycles statuses of
    Nothing -> do
      maybeForeigns <- readMVar dmvar
      case maybeForeigns of
        Nothing -> return (Left Exit.BP_CannotLoadDependencies)
        Just fs -> return (Right fs)
    Just (NE.List name names) -> do
      _ <- readMVar dmvar
      return (Left (Exit.BP_Cycle name names))

-- =============================================================================
-- REPL Build Functions
-- =============================================================================

-- | Build artifacts for REPL interaction.
--
-- Handles building a single module in REPL context, including dependency
-- resolution and interface loading. This is optimized for fast iteration
-- during interactive development.
--
-- ==== REPL Build Process
--
-- 1. Parse the input source
-- 2. Crawl dependencies of the REPL module
-- 3. Check project integrity and load interfaces
-- 4. Compile the module with fresh dependencies
-- 5. Generate REPL-specific artifacts
--
-- ==== Parameters
--
-- [@root@]: Project root directory
-- [@details@]: Project configuration details
-- [@source@]: Source code to compile in REPL context
--
-- ==== Errors
--
-- Returns 'Exit.Repl' for:
--
-- * Syntax errors in source code
-- * Missing or cyclic dependencies
-- * Compilation failures
-- * Interface loading problems
--
-- @since 0.19.1
fromRepl :: FilePath -> Details.Details -> B.ByteString -> IO (Either Exit.Repl ReplArtifacts)
fromRepl root details source = do
  env@(Env _ _ projectType _ _ _ _) <- createReplEnvironment root details
  case Parse.fromByteString projectType source of
    Left syntaxError ->
      (return . Left) . Exit.ReplBadInput source $ Error.BadSyntax syntaxError
    Right modul -> processReplModule env root details source modul

-- | Create a REPL-specific build environment.
--
-- Creates an environment optimized for REPL usage with the ignorer key
-- to suppress unnecessary build output during interactive development.
--
-- @since 0.19.1
createReplEnvironment :: FilePath -> Details.Details -> IO Env
createReplEnvironment root (Details.Details _ validOutline buildID locals foreigns _) =
  case validOutline of
    Details.ValidApp givenSrcDirs -> do
      srcDirs <- traverse (toAbsoluteSrcDir root) (NE.toList givenSrcDirs)
      pure $ Env Reporting.ignorer root Parse.Application srcDirs buildID locals foreigns
    Details.ValidPkg pkg _ _ -> do
      srcDir <- toAbsoluteSrcDir root (Outline.RelativeSrcDir "src")
      pure $ Env Reporting.ignorer root (Parse.Package pkg) [srcDir] buildID locals foreigns

-- | Process a parsed REPL module through the build pipeline.
--
-- Handles dependency crawling, compilation, and artifact generation
-- for a single REPL module. This is the main coordination function
-- for REPL module processing.
--
-- ==== Processing Steps
--
-- 1. Load project interfaces
-- 2. Crawl module dependencies
-- 3. Validate project integrity
-- 4. Compile with resolved dependencies
-- 5. Generate REPL artifacts
--
-- @since 0.19.1
processReplModule :: Env -> FilePath -> Details.Details -> B.ByteString -> Src.Module -> IO (Either Exit.Repl ReplArtifacts)
processReplModule env root details source modul@(Src.Module _ _ _ imports _ _ _ _ _ _) = do
  dmvar <- Details.loadInterfaces root details
  
  statuses <- crawlReplDependencies env imports
  midpoint <- checkMidpoint dmvar statuses
  
  case midpoint of
    Left problem ->
      return . Left $ Exit.ReplProjectProblem problem
    Right foreigns ->
      compileReplModule env root details source modul foreigns statuses

-- | Crawl dependencies for a REPL module.
--
-- Optimized dependency crawling that only processes the specific imports
-- needed by the REPL module, avoiding unnecessary work for faster iteration.
--
-- ==== Optimization Strategy
--
-- * Only crawls explicitly imported modules
-- * Uses existing MVar coordination for thread safety
-- * Leverages cached results where possible
--
-- @since 0.19.1
crawlReplDependencies :: Env -> [Src.Import] -> IO (Map ModuleName.Raw Status)
crawlReplDependencies env imports = do
  let deps = fmap Src.getImportName imports
  mvar <- newMVar Map.empty
  Crawl.crawlDeps env mvar deps ()
  readMVar mvar >>= traverse readMVar

-- | Compile a REPL module and generate artifacts.
--
-- Handles the final compilation phase for REPL modules, including
-- dependency checking, module compilation, and artifact generation
-- optimized for REPL usage.
--
-- ==== Compilation Process
--
-- 1. Set up compilation coordination (MVars)
-- 2. Compile all dependency modules in parallel
-- 3. Check dependency status and resolve conflicts
-- 4. Generate REPL-specific artifacts
-- 5. Write updated details to disk
--
-- @since 0.19.1
compileReplModule :: Env -> FilePath -> Details.Details -> B.ByteString -> Src.Module -> Dependencies -> Map ModuleName.Raw Status -> IO (Either Exit.Repl ReplArtifacts)
compileReplModule env root details source modul foreigns statuses = do
  -- Compile modules and get both MVars and resolved results
  rmvar <- newEmptyMVar
  resultMVars <- forkWithKey (Check.checkModule (CheckConfig env foreigns rmvar)) statuses
  putMVar rmvar resultMVars
  results <- traverse readMVar resultMVars
  Validation.writeDetails root details results
  
  deps <- extractModuleDependencies modul
  depsStatus <- Dependencies.checkDeps (DepsConfig root resultMVars deps 0)
  let replConfig = Validation.ReplConfig env source modul resultMVars
  Validation.finalizeReplArtifacts replConfig depsStatus results

-- | Extract dependencies from a parsed module.
--
-- Extracts the list of imported module names from a parsed source module
-- for use in dependency checking and resolution.
--
-- @since 0.19.1
extractModuleDependencies :: Src.Module -> IO [ModuleName.Raw]
extractModuleDependencies (Src.Module _ _ _ imports _ _ _ _ _ _) =
  pure $ fmap Src.getImportName imports

-- | Fork a computation for each key-value pair in a Map.
--
-- Specialized version of forkWithKey for REPL compilation needs.
-- Applies the given function to each key-value pair in a separate thread,
-- returning a Map of MVars containing the results.
--
-- @since 0.19.1
{-# INLINE forkWithKey #-}
forkWithKey :: (k -> a -> IO b) -> Map k a -> IO (Map k (MVar b))
forkWithKey func = Map.traverseWithKey (\k v -> forkComputation (func k v))

-- | Fork a single computation for REPL compilation.
--
-- Creates a separate thread for the computation and returns an MVar
-- that will contain the result when the computation completes.
--
-- @since 0.19.1
forkComputation :: IO a -> IO (MVar a)
forkComputation work = do
  mvar <- newEmptyMVar
  _ <- Control.Concurrent.forkIO $ work >>= putMVar mvar
  return mvar

-- | Convert a source directory to an absolute path.
--
-- Handles both absolute and relative source directories, canonicalizing
-- the final path to ensure consistent path resolution across the build.
-- This is a specialized version for REPL usage.
--
-- @since 0.19.1
toAbsoluteSrcDir :: FilePath -> Outline.SrcDir -> IO AbsoluteSrcDir
toAbsoluteSrcDir root srcDir =
  AbsoluteSrcDir
    <$> Dir.canonicalizePath
      ( case srcDir of
          Outline.AbsoluteSrcDir dir -> dir
          Outline.RelativeSrcDir dir -> root </> dir
      )