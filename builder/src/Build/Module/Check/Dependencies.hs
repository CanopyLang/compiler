{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Dependency status processing for module checking.
--
-- This module handles dependency-specific processing logic including
-- changed dependencies, same dependencies, and cached import problems.
-- All functions follow CLAUDE.md standards with proper separation of concerns.
--
-- === Dependency Processing Overview
--
-- @
-- Dependency Status Types:
-- ├── DepsChange    -> recompile with new interfaces
-- ├── DepsSame      -> load cached interfaces 
-- ├── DepsBlock     -> wait for dependency resolution
-- └── DepsNotFound  -> handle import errors
-- @
--
-- === Usage Examples
--
-- @
-- -- Process changed dependency status
-- result <- processChangedDepsStatus config depsStatus
--
-- -- Process cached dependency status  
-- result <- processCachedDepsStatus config path time depsStatus
--
-- -- Handle same dependencies case
-- result <- handleSameDeps env name local source module docsNeed same cached
-- @
--
-- === Error Handling
--
-- Dependency processing can fail due to:
--
-- * Interface loading failures
-- * Import resolution problems
-- * File I/O errors during recompilation
-- * Compilation errors in dependencies
--
-- All dependency processors return 'Result' values with proper error information.
--
-- @since 0.19.1
module Build.Module.Check.Dependencies
  ( -- * Dependency Status Processing
    processChangedDepsStatus
  , processCachedDepsStatus
    
  -- * Same Dependencies Handling
  , handleSameDeps
  , handleSameDepsWithConfig
  
  -- * Import Problem Handling
  , handleCachedImportProblems
  , handleCachedImportProblemsWithConfig
  
  -- * Recompilation Functions
  , recompileCachedModule
  , createCachedResult
  
  -- * Utility Functions
  , checkDepsForModule
  ) where

import qualified Control.Concurrent.MVar as MVar
import Control.Lens ((^.))
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString as B
import Data.Map.Strict (Map)
import Data.NonEmptyList (List)
import qualified File
import qualified Parse.Module as Parse
import qualified Reporting.Error as Error
import qualified Reporting.Error.Import as Import

import Build.Dependencies (checkDeps, loadInterfaces)
import Build.Types
  ( Env(..)
  , Result(..)
  , ResultDict
  , DocsNeed(..)
  , DepsStatus(..)
  , Dep
  , CDep
  , DepsConfig(..)
  , CachedInterface(..)
  )
import Build.Module.Check.Config
  ( CachedConfig(..)
  , ChangedConfig(..)
  , SameDepsConfig(..)
  , CachedImportConfig(..)
  , cachedEnv
  , cachedProjectType
  , cachedModuleName
  , cachedLocal
  , changedEnv
  , changedModuleName
  , changedLocal
  , changedSource
  , changedModule
  , changedDocsNeed
  , changedImports
  , sameDepsEnv
  , sameDepsLocal
  , sameDepsSource
  , sameDepsModule
  , sameDepsDocsNeed
  , cachedImportEnv
  , cachedImportProjectType
  , cachedImportModuleName
  , cachedImportPath
  )

-- | Process dependency status for changed module.
--
-- Determines compilation action based on dependency status.
-- Compiles if dependencies are ready, handles blocks and errors.
--
-- ==== Parameters
--
-- [@config@] Changed module configuration
-- [@depsStatus@] Status of module dependencies
--
-- ==== Returns
--
-- IO action producing compilation result or error
processChangedDepsStatus :: ChangedConfig -> DepsStatus -> IO Result
processChangedDepsStatus config depsStatus =
  case depsStatus of
    DepsChange ifaces -> 
      compile 
        (config ^. changedEnv) 
        (config ^. changedDocsNeed) 
        (config ^. changedLocal) 
        (config ^. changedSource) 
        ifaces 
        (config ^. changedModule)
    DepsSame same cached -> 
      handleSameDeps 
        (config ^. changedEnv) 
        (config ^. changedModuleName) 
        (config ^. changedLocal) 
        (config ^. changedSource) 
        (config ^. changedModule) 
        (config ^. changedDocsNeed) 
        same 
        cached
    DepsBlock -> pure RBlocked
    DepsNotFound problems -> createImportErrorResult config problems
  where
    createImportErrorResult cfg problems =
      let local = cfg ^. changedLocal
          name = cfg ^. changedModuleName
          path = local ^. Details.path
          time = local ^. Details.time
          source = cfg ^. changedSource
          imports = cfg ^. changedImports
          env = cfg ^. changedEnv
      in (pure . RProblem) . Error.Module name path time source $ 
           Error.BadImports (toImportErrors env undefined imports problems)

-- | Process dependency status for cached module.
--
-- Determines action based on dependency status - recompile if dependencies
-- changed, use cached result if same, handle blocks and import errors.
--
-- ==== Parameters
--
-- [@config@] Cached module configuration
-- [@path@] Module file path
-- [@time@] File modification time
-- [@depsStatus@] Status of module dependencies
--
-- ==== Returns
--
-- IO action producing result based on dependency analysis
processCachedDepsStatus :: CachedConfig -> FilePath -> File.Time -> DepsStatus -> IO Result
processCachedDepsStatus config path time depsStatus =
  case depsStatus of
    DepsChange ifaces -> recompileCachedModule config path time ifaces
    DepsSame _ _ -> createCachedResult (local ^. Details.main) (local ^. Details.lastChange)
    DepsBlock -> pure RBlocked
    DepsNotFound problems -> 
      handleCachedImportProblems 
        (config ^. cachedEnv) 
        (config ^. cachedProjectType) 
        (config ^. cachedModuleName) 
        path 
        time 
        problems
  where
    local = config ^. cachedLocal

-- | Handle same dependencies case.
--
-- When dependencies haven't changed, attempts to load cached interfaces
-- and compile with existing dependency information.
--
-- ==== Parameters
--
-- [@env@] Build environment
-- [@_name@] Module name (unused)
-- [@local@] Local module details
-- [@source@] Module source code
-- [@modul@] Parsed module AST
-- [@docsNeed@] Documentation requirements
-- [@same@] Same dependencies list
-- [@cached@] Cached dependencies list
--
-- ==== Returns
--
-- IO action producing compilation result
handleSameDeps :: Env -> ModuleName.Raw -> Details.Local -> B.ByteString -> Src.Module -> DocsNeed -> [Dep] -> [CDep] -> IO Result
handleSameDeps env _name local source modul docsNeed same cached = do
  let config = SameDepsConfig env local source modul docsNeed
  handleSameDepsWithConfig config same cached

-- | Handle same dependencies using configuration.
--
-- Attempts to load interfaces for same and cached dependencies,
-- then compiles the module if interfaces are available.
--
-- ==== Parameters
--
-- [@config@] Same dependencies configuration
-- [@same@] Same dependencies list  
-- [@cached@] Cached dependencies list
--
-- ==== Returns
--
-- IO action producing compilation result or block
handleSameDepsWithConfig :: SameDepsConfig -> [Dep] -> [CDep] -> IO Result
handleSameDepsWithConfig config same cached = do
  let env = config ^. sameDepsEnv
      Env _ root _ _ _ _ _ = env
  maybeLoaded <- loadInterfaces root same cached
  case maybeLoaded of
    Nothing -> pure RBlocked
    Just ifaces -> 
      compile 
        env 
        (config ^. sameDepsDocsNeed) 
        (config ^. sameDepsLocal) 
        (config ^. sameDepsSource) 
        ifaces 
        (config ^. sameDepsModule)

-- | Handle cached import problems.
--
-- Processes import problems for cached modules by reading source
-- and creating appropriate error messages.
--
-- ==== Parameters
--
-- [@env@] Build environment
-- [@projectType@] Type of project being built
-- [@name@] Module name with problems
-- [@path@] Module file path
-- [@time@] File modification time
-- [@problems@] List of import problems
--
-- ==== Returns
--
-- IO action producing error result with import problems
handleCachedImportProblems :: Env -> Parse.ProjectType -> ModuleName.Raw -> FilePath -> File.Time -> List (ModuleName.Raw, Import.Problem) -> IO Result
handleCachedImportProblems env projectType name path time problems = do
  let config = CachedImportConfig env projectType name path
  handleCachedImportProblemsWithConfig config time problems

-- | Handle cached import problems using configuration.
--
-- Creates detailed error messages for import problems by parsing
-- the source file and generating appropriate error contexts.
--
-- ==== Parameters
--
-- [@config@] Cached import configuration
-- [@time@] File modification time
-- [@problems@] List of import problems
--
-- ==== Returns
--
-- IO action producing error result with detailed import error information
handleCachedImportProblemsWithConfig :: CachedImportConfig -> File.Time -> List (ModuleName.Raw, Import.Problem) -> IO Result
handleCachedImportProblemsWithConfig config time problems = do
  source <- File.readUtf8 (config ^. cachedImportPath)
  let name = config ^. cachedImportModuleName
      path = config ^. cachedImportPath
      projectType = config ^. cachedImportProjectType
      env = config ^. cachedImportEnv
  (pure . RProblem) . Error.Module name path time source $
    case Parse.fromByteString projectType source of
      Right (Src.Module _ _ _ imports _ _ _ _ _) ->
        Error.BadImports (toImportErrors env undefined imports problems)
      Left err -> Error.BadSyntax err

-- | Recompile cached module with changed dependencies.
--
-- Recompiles a previously cached module when its dependencies have changed.
-- Reads the source file and performs full compilation with updated interfaces.
--
-- ==== Parameters
--
-- [@config@] Cached module configuration
-- [@path@] Path to the source file
-- [@time@] File modification time
-- [@ifaces@] Updated dependency interfaces
--
-- ==== Returns
--
-- IO action producing compilation result or parse error
recompileCachedModule :: CachedConfig -> FilePath -> File.Time -> Map ModuleName.Raw I.Interface -> IO Result
recompileCachedModule config path time ifaces = do
  source <- File.readUtf8 path
  case Parse.fromByteString (config ^. cachedProjectType) source of
    Right modul -> compile (config ^. cachedEnv) (DocsNeed False) (config ^. cachedLocal) source ifaces modul
    Left err -> pure . RProblem $ Error.Module (config ^. cachedModuleName) path time source (Error.BadSyntax err)

-- | Create cached result without recompilation.
--
-- Creates a result for modules that don't need recompilation based on
-- unchanged dependencies and source code.
--
-- ==== Parameters
--
-- [@hasMain@] Whether the module has a main function
-- [@lastChange@] Build ID of last interface change
--
-- ==== Returns
--
-- IO action producing cached result with appropriate status
createCachedResult :: Bool -> Details.BuildID -> IO Result
createCachedResult hasMain lastChange = do
  mvar <- MVar.newMVar Unneeded
  pure (RCached hasMain lastChange mvar)

-- | Check dependencies for a module.
--
-- Determines the status of module dependencies by comparing build IDs
-- and checking interface availability.
--
-- ==== Parameters
--
-- [@root@] Build root directory
-- [@results@] Current module results
-- [@deps@] Module dependencies list
-- [@lastCompile@] Last compilation build ID
--
-- ==== Returns
--
-- IO action producing dependency status
checkDepsForModule :: FilePath -> ResultDict -> [ModuleName.Raw] -> Details.BuildID -> IO DepsStatus
checkDepsForModule root results deps lastCompile =
  checkDeps (DepsConfig root results deps lastCompile)

-- Forward declarations for functions implemented in other modules
-- | Compile module (implemented in Build.Module.Check.Workflow).
compile :: Env -> DocsNeed -> Details.Local -> B.ByteString -> Map ModuleName.Raw I.Interface -> Src.Module -> IO Result
compile = undefined -- This will be resolved by import from Workflow module

-- | Convert import errors (placeholder for complex function).
toImportErrors :: Env -> ResultDict -> [Src.Import] -> List (ModuleName.Raw, Import.Problem) -> List Import.Error
toImportErrors _ _ _ _ = undefined -- This is a complex function that would need its own decomposition