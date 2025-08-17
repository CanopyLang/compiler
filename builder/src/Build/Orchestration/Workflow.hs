{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Main build workflow orchestration for the Canopy compiler.
--
-- This module provides the core build workflow coordination functionality,
-- managing the complete build process from module crawling through compilation
-- and documentation generation. It handles the main entry point for building
-- from exposed modules and coordinates all build phases.
--
-- === Primary Responsibilities
--
-- * Main build workflow coordination ('fromExposed')
-- * Build phase orchestration (crawl and compile phases)
-- * Module compilation coordination
-- * Environment and threading utilities
-- * Build configuration management
--
-- === Usage Examples
--
-- @
-- -- Build from exposed modules
-- let config = ExposedBuildConfig style root details goal
-- result <- fromExposed config exposedModules
-- case result of
--   Left problem -> handleBuildError problem
--   Right docs -> processDocs docs
--
-- -- Create build environment
-- env <- makeEnv key root details
-- let srcDirs = env ^. envSrcDirs
-- @
--
-- === Build Workflow Process
--
-- The build workflow follows these coordinated steps:
--
-- 1. Environment setup and validation
-- 2. Module crawling and dependency discovery
-- 3. Midpoint checking for cycles and dependencies  
-- 4. Module compilation and checking
-- 5. Result finalization and documentation generation
--
-- === Threading and Concurrency
--
-- Build workflow uses MVars for coordinating concurrent operations
-- across the crawl and compile phases. All shared state is properly
-- synchronized through the Build.Types coordination mechanisms.
--
-- @since 0.19.1
module Build.Orchestration.Workflow
  ( -- * Main Build Functions
    fromExposed
  , ExposedBuildConfig (..)
    
  -- * Environment Management  
  , makeEnv
  , toAbsoluteSrcDir
  , addRelative
    
  -- * Build Phase Coordination
  , performCrawlPhase
  , performCompilePhase
  , compileModules
    
  -- * Threading Utilities
  , fork
  , forkWithKey
    
  -- * Configuration Lenses
  , ebcStyle
  , ebcRoot
  , ebcDetails
  , ebcDocsGoal
  ) where

-- Canopy-specific imports
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline

-- Build system modules
import Build.Config (CheckConfig (..), CrawlConfig (..))
import qualified Build.Crawl as Crawl
import qualified Build.Module.Check as Check
import Build.Types
  ( Env (..)
  , AbsoluteSrcDir (..)
  , Status (..)
  , DocsNeed (..)
  , DocsGoal (..)
  , Dependencies
  , Result
  )
import qualified Build.Validation as Validation

-- Parser and AST imports
import qualified Parse.Module as Parse

-- Standard library imports
import Control.Concurrent.MVar
  ( MVar
  , newEmptyMVar
  , putMVar
  , readMVar
  )
import qualified Control.Concurrent as Concurrent
import qualified Data.Foldable as Foldable
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Map.Utils as MapUtils
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified System.Directory as Dir
import System.FilePath ((</>))
import Control.Lens (makeLenses)

-- =============================================================================
-- Project Validation Functions  
-- =============================================================================
-- Local implementation to avoid circular imports between Build.Orchestration
-- and Build.Orchestration.Workflow modules.

-- | Check project integrity at the midpoint of the build.
--
-- Local implementation to avoid circular imports between Build.Orchestration
-- and Build.Orchestration.Workflow modules.
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
-- Configuration Types and Utilities
-- =============================================================================

-- | Configuration for building exposed modules.
--
-- Groups build parameters to meet CLAUDE.md requirement of ≤4 parameters.
-- Contains all necessary configuration for coordinating the main build workflow.
--
-- @since 0.19.1
data ExposedBuildConfig docs = ExposedBuildConfig
  { _ebcStyle :: !Reporting.Style
    -- ^ Reporting style for build output
  , _ebcRoot :: !FilePath
    -- ^ Project root directory
  , _ebcDetails :: !Details.Details
    -- ^ Project details and configuration
  , _ebcDocsGoal :: !(DocsGoal docs)
    -- ^ Documentation generation goal
  } deriving ()

-- Generate lenses for configuration
makeLenses ''ExposedBuildConfig

-- | Create a build environment from project details.
--
-- Constructs an 'Env' with the appropriate source directories based on
-- whether this is an application or package build. Applications can have
-- multiple source directories, while packages use a single "src" directory.
--
-- ==== Examples
--
-- >>> env <- makeEnv key "/path/to/project" details
-- >>> case env ^. envProjectType of
-- >>>   Parse.Application -> putStrLn "Building application"
-- >>>   Parse.Package pkg -> putStrLn $ "Building package: " <> show pkg
--
-- @since 0.19.1
makeEnv :: Reporting.BKey -> FilePath -> Details.Details -> IO Env
makeEnv key root (Details.Details _ validOutline buildID locals foreigns _) =
  case validOutline of
    Details.ValidApp givenSrcDirs -> do
      srcDirs <- traverse (toAbsoluteSrcDir root) (NE.toList givenSrcDirs)
      pure $ Env key root Parse.Application srcDirs buildID locals foreigns
    Details.ValidPkg pkg _ _ -> do
      srcDir <- toAbsoluteSrcDir root (Outline.RelativeSrcDir "src")
      pure $ Env key root (Parse.Package pkg) [srcDir] buildID locals foreigns

-- | Convert a source directory to an absolute path.
--
-- Handles both absolute and relative source directories, canonicalizing
-- the final path to ensure consistent path resolution across the build.
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

-- | Add a relative path to an absolute source directory.
--
-- Utility function for constructing file paths within source directories
-- while maintaining the absolute path invariant.
--
-- @since 0.19.1
addRelative :: AbsoluteSrcDir -> FilePath -> FilePath
addRelative (AbsoluteSrcDir srcDir) path =
  srcDir </> path

-- | Fork a computation into a separate thread.
--
-- Returns an MVar that will contain the result when the computation completes.
-- Used for parallelizing independent build operations.
--
-- @since 0.19.1
fork :: IO a -> IO (MVar a)
fork work = do
  mvar <- newEmptyMVar
  _ <- Concurrent.forkIO $ work >>= putMVar mvar
  return mvar

-- | Fork a computation for each key-value pair in a Map.
--
-- Applies the given function to each key-value pair in a separate thread,
-- returning a Map of MVars containing the results.
--
-- @since 0.19.1
{-# INLINE forkWithKey #-}
forkWithKey :: (k -> a -> IO b) -> Map k a -> IO (Map k (MVar b))
forkWithKey func =
  Map.traverseWithKey (\k v -> fork (func k v))

-- | Build artifacts from a list of exposed modules.
--
-- This is the main entry point for building applications and packages.
-- It orchestrates the complete build process from module crawling through
-- compilation and documentation generation.
--
-- The build process:
--
-- 1. Creates build environment
-- 2. Crawls modules to discover dependencies  
-- 3. Validates project structure and checks for cycles
-- 4. Compiles modules and checks interfaces
-- 5. Finalizes build artifacts and generates documentation
--
-- ==== Parameters
--
-- [@config@]: Build configuration with style, root, details, and docs goal
-- [@exposed@]: List of module names to build
--
-- ==== Errors
--
-- Returns 'Exit.BuildProblem' for:
--
-- * Project configuration errors
-- * Cyclic dependencies
-- * Missing dependencies
-- * Compilation failures
-- * Documentation generation errors
--
-- @since 0.19.1
fromExposed :: ExposedBuildConfig docs -> List ModuleName.Raw -> IO (Either Exit.BuildProblem docs)
fromExposed (ExposedBuildConfig style root details docsGoal) exposed =
  Reporting.trackBuild style $ \key -> do
    env <- makeEnv key root details
    dmvar <- Details.loadInterfaces root details
    
    statuses <- performCrawlPhase env dmvar docsGoal exposed
    performCompilePhase env dmvar root details docsGoal exposed statuses

-- | Perform the module crawling phase.
--
-- Crawls modules to discover dependencies and build the dependency graph.
--
-- @since 0.19.1
performCrawlPhase :: Env -> MVar (Maybe Dependencies) -> DocsGoal docs -> List ModuleName.Raw -> IO (Map ModuleName.Raw Status)
performCrawlPhase env _dmvar docsGoal (NE.List e es) = do
  mvar <- newEmptyMVar
  let docsNeed = toDocsNeed docsGoal
  roots <- MapUtils.fromKeysA (fork . Crawl.crawlModule (CrawlConfig env mvar docsNeed)) (e : es)
  putMVar mvar roots
  Foldable.traverse_ readMVar roots
  readMVar mvar >>= traverse readMVar

-- | Perform the compilation phase.
--
-- Compiles modules and generates final artifacts or documentation.
--
-- @since 0.19.1
performCompilePhase :: Env -> MVar (Maybe Dependencies) -> FilePath -> Details.Details -> DocsGoal docs -> List ModuleName.Raw -> Map ModuleName.Raw Status -> IO (Either Exit.BuildProblem docs)
performCompilePhase env dmvar root details docsGoal exposed statuses = do
  midpoint <- checkMidpoint dmvar statuses
  case midpoint of
    Left problem ->
      return (Left (Exit.BuildProjectProblem problem))
    Right foreigns -> do
      results <- compileModules env foreigns statuses
      Validation.writeDetails root details results
      Validation.finalizeExposed root docsGoal exposed results

-- | Compile all modules using forked workers.
--
-- Coordinates parallel compilation of all modules in the dependency graph.
--
-- @since 0.19.1
compileModules :: Env -> Dependencies -> Map ModuleName.Raw Status -> IO (Map ModuleName.Raw Result)
compileModules env foreigns statuses = do
  rmvar <- newEmptyMVar
  resultMVars <- forkWithKey (Check.checkModule (CheckConfig env foreigns rmvar)) statuses
  putMVar rmvar resultMVars
  traverse readMVar resultMVars

-- | Convert documentation goal to documentation need flag.
toDocsNeed :: DocsGoal a -> DocsNeed
toDocsNeed goal =
  case goal of
    IgnoreDocs -> DocsNeed False
    WriteDocs _ -> DocsNeed True
    KeepDocs -> DocsNeed True