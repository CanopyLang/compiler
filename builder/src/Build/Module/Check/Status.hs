{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module status processing for the Build system.
--
-- This module handles all status-specific processing logic for modules,
-- including cached, changed, bad import, bad syntax, foreign, and kernel status types.
-- Each status type has dedicated processing logic following CLAUDE.md standards.
--
-- === Status Processing Overview
--
-- @
-- Module Status Types:
-- ├── SCached      -> processCachedStatus
-- ├── SChanged     -> processChangedStatus  
-- ├── SBadImport   -> processBadImportStatus
-- ├── SBadSyntax   -> processBadSyntaxStatus
-- ├── SForeign     -> processForeignStatus
-- └── SKernel      -> processKernelStatus
-- @
--
-- === Usage Examples
--
-- @
-- -- Process a cached module status
-- result <- processCachedStatus env resultsMVar moduleName localDetails
--
-- -- Process a changed module status  
-- result <- processChangedStatus env resultsMVar moduleName localDetails source module docsNeed
--
-- -- Process foreign module status
-- result <- processForeignStatus dependencies packageName moduleName
-- @
--
-- === Error Handling
--
-- Status processing can fail due to:
--
-- * Dependency resolution failures
-- * Compilation errors
-- * File I/O issues
-- * Interface loading problems
--
-- All status processors return 'Result' values with proper error information.
--
-- === Thread Safety
--
-- Status processing operations are thread-safe through proper MVar usage
-- and immutable data structures.
--
-- @since 0.19.1
module Build.Module.Check.Status
  ( -- * Main Status Processing
    processModuleStatus
  , processModuleStatusWithConfig
    
  -- * Individual Status Processors  
  , processCachedStatus
  , processChangedStatus
  
  -- * Re-exported Core Status Processors
  , module Build.Module.Check.Status.Core
  
  -- * Re-exported Configuration Types
  , module Build.Module.Check.Config
  
  -- * Re-exported Dependency Processing
  , module Build.Module.Check.Dependencies
  ) where

import Control.Concurrent.MVar (MVar)
import qualified Control.Concurrent.MVar as MVar
import Control.Lens ((^.))
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString as B
import qualified File

import Build.Module.Check.Dependencies
  ( processChangedDepsStatus
  , processCachedDepsStatus
  , handleCachedImportProblems
  , checkDepsForModule
  )
import Build.Module.Check.Workflow
  ( recompileCachedModule
  , createCachedResult
  )
import Build.Module.Check.Status.Core
  ( processBadImportStatus
  , processBadSyntaxStatus
  , processForeignStatus
  , processKernelStatus
  )
import Build.Types
  ( Env(..)
  , Dependencies
  , Status(..)
  , Result(..)
  , ResultDict
  , DocsNeed(..)
  , DepsStatus(..)
  )
import Build.Module.Check.Config
  ( ModuleStatusConfig(..)
  , CachedConfig(..)
  , ChangedConfig(..)
  , SameDepsConfig(..)
  , CachedImportConfig(..)
  , moduleStatusEnv
  , moduleStatusForeigns
  , moduleStatusResultsMVar
  , moduleStatusName
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


-- | Process module status to determine result.
--
-- This function dispatches to the appropriate status processor based on the
-- status type, using the provided environment and dependencies.
--
-- ==== Parameters
--
-- [@env@] The build environment containing configuration
-- [@foreigns@] Foreign module dependencies
-- [@resultsMVar@] Shared results for dependency resolution
-- [@name@] Module name being processed
-- [@status@] Current module status
--
-- ==== Returns
--
-- IO action producing a 'Result' for the module processing
processModuleStatus :: Env -> Dependencies -> MVar ResultDict -> ModuleName.Raw -> Status -> IO Result
processModuleStatus env foreigns resultsMVar name status =
  let config = ModuleStatusConfig env foreigns resultsMVar name
  in processModuleStatusWithConfig config status

-- | Process module status using configuration record.
--
-- Dispatches to appropriate status processor based on status type.
-- This function implements the main status processing logic with proper
-- configuration management.
--
-- ==== Parameters
--
-- [@config@] Module status configuration
-- [@status@] Module status to process
--
-- ==== Returns
--
-- IO action producing the processing result
processModuleStatusWithConfig :: ModuleStatusConfig -> Status -> IO Result
processModuleStatusWithConfig config status =
  case status of
    SCached local -> 
      processCachedStatus 
        (config ^. moduleStatusEnv) 
        (config ^. moduleStatusResultsMVar) 
        (config ^. moduleStatusName) 
        local
    SChanged local source modul docsNeed -> 
      processChangedStatus 
        (config ^. moduleStatusEnv) 
        (config ^. moduleStatusResultsMVar) 
        (config ^. moduleStatusName) 
        local 
        source 
        modul 
        docsNeed
    SBadImport importProblem -> 
      processBadImportStatus importProblem
    _ -> processOtherStatuses config status
  where
    processOtherStatuses cfg st = case st of
      SBadSyntax path time source err -> 
        processBadSyntaxStatus (cfg ^. moduleStatusName) path time source err
      SForeign home -> 
        processForeignStatus (cfg ^. moduleStatusForeigns) home (cfg ^. moduleStatusName)
      SKernel -> 
        processKernelStatus
      _ -> error "Unexpected status in processOtherStatuses"


-- | Process cached module status.
--
-- Handles modules that were previously compiled and cached. Checks if
-- dependencies have changed and recompiles if necessary.
--
-- ==== Parameters
--
-- [@env@] Build environment
-- [@resultsMVar@] Shared results for dependency checking
-- [@name@] Module name being processed  
-- [@local@] Local module details from cache
--
-- ==== Returns
--
-- IO action producing appropriate result based on dependency status
processCachedStatus :: Env -> MVar ResultDict -> ModuleName.Raw -> Details.Local -> IO Result
processCachedStatus env@(Env _ root projectType _ _ _ _) resultsMVar name local = do
  let path = local ^. Details.path
  let time = local ^. Details.time
  let deps = local ^. Details.deps
  let lastCompile = local ^. Details.lastCompile
  results <- MVar.readMVar resultsMVar
  depsStatus <- checkDepsForModule root results deps lastCompile
  let config = CachedConfig
        { _cachedEnv = env
        , _cachedProjectType = projectType
        , _cachedModuleName = name
        , _cachedLocal = local
        }
  Build.Module.Check.Status.processCachedDepsStatus config path time depsStatus

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

-- | Process changed module status.
--
-- Handles modules that have been modified since last compilation.
-- Checks dependencies and compiles if ready.
--
-- ==== Parameters
--
-- [@env@] Build environment
-- [@resultsMVar@] Shared results for dependency checking
-- [@name@] Module name being processed
-- [@local@] Local module details
-- [@source@] Module source code
-- [@modul@] Parsed module AST
-- [@docsNeed@] Documentation requirements
--
-- ==== Returns
--
-- IO action producing compilation result
processChangedStatus :: Env -> MVar ResultDict -> ModuleName.Raw -> Details.Local -> B.ByteString -> Src.Module -> DocsNeed -> IO Result
processChangedStatus env@(Env _ root _ _ _ _ _) resultsMVar name local source modul@(Src.Module _ _ _ imports _ _ _ _ _) docsNeed = do
  let deps = local ^. Details.deps
  let lastCompile = local ^. Details.lastCompile
  results <- MVar.readMVar resultsMVar
  depsStatus <- checkDepsForModule root results deps lastCompile
  let config = ChangedConfig
        { _changedEnv = env
        , _changedModuleName = name
        , _changedLocal = local
        , _changedSource = source
        , _changedModule = modul
        , _changedDocsNeed = docsNeed
        , _changedImports = imports
        }
  processChangedDepsStatus config depsStatus







