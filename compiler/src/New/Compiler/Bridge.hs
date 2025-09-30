{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Bridge between new query-based compiler and old Build system.
--
-- This module provides compatibility layer that wraps the new compiler
-- to produce Build.Artifacts compatible with the existing build system.
-- This enables gradual migration with environment flag switching.
--
-- Usage:
--
-- @
-- -- Use new compiler via environment variable
-- artifacts <- compileFromPaths style root details paths
-- @
--
-- @since 0.19.1
module New.Compiler.Bridge
  ( -- * Main Interface
    compileFromPaths,

    -- * Environment Flag
    shouldUseNewCompiler,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Build.Types as Build
import qualified Canopy.Details as Details
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Concurrent.STM (atomically, readTVar)
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified New.Compiler.Debug.Logger as Logger
import New.Compiler.Debug.Logger (DebugCategory (..))
import qualified New.Compiler.Driver as Driver
import qualified New.Compiler.Query.Simple as Simple
import qualified Parse.Module as Parse
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified System.Environment as Env

-- | Check if new compiler should be used.
--
-- Reads CANOPY_NEW_COMPILER environment variable.
-- Returns True if set to "1", False otherwise.
shouldUseNewCompiler :: IO Bool
shouldUseNewCompiler = do
  maybeFlag <- Env.lookupEnv "CANOPY_NEW_COMPILER"
  let useNew = maybeFlag == Just "1"
  Logger.debug COMPILE_DEBUG ("shouldUseNewCompiler: flag=" ++ show maybeFlag ++ ", useNew=" ++ show useNew)
  return useNew

-- | Compile from file paths using new query-based compiler.
--
-- This is the main bridge function that:
-- 1. Extracts project configuration from Details
-- 2. Loads dependency modules from GlobalGraph
-- 3. Compiles each module using new compiler
-- 4. Wraps results in Build.Artifacts format with ALL modules
compileFromPaths ::
  Reporting.Style ->
  FilePath ->
  Details.Details ->
  List FilePath ->
  IO (Either Exit.BuildProblem Build.Artifacts)
compileFromPaths _style root details paths = do
  Logger.debug COMPILE_DEBUG "Bridge: Using new compiler"
  Logger.debug COMPILE_DEBUG ("Bridge: Root = " ++ root)
  Logger.debug COMPILE_DEBUG ("Bridge: Paths = " ++ show (NE.toList paths))

  let pkg = extractPackageName details
  Logger.debug COMPILE_DEBUG ("Bridge: Package = " ++ show pkg)

  -- Load BOTH interfaces and raw dependency interfaces
  (ifaces, depInterfaces) <- loadAllInterfacesFromDetails root details
  Logger.debug COMPILE_DEBUG ("Bridge: Loaded " ++ show (Map.size ifaces) ++ " public interfaces")
  Logger.debug COMPILE_DEBUG ("Bridge: Loaded " ++ show (Map.size depInterfaces) ++ " dependency interfaces")

  -- Load dependency modules (CRITICAL: This contains elm/html, elm/core, etc.)
  depModules <- loadDependencyModules root details
  Logger.debug COMPILE_DEBUG ("Bridge: Loaded " ++ show (length depModules) ++ " dependency modules")

  let projectType = extractProjectType details
  Logger.debug COMPILE_DEBUG "Bridge: Extracted project type"

  -- Compile each path
  compileResult <- compileAllPaths pkg ifaces depInterfaces projectType (NE.toList paths)

  case compileResult of
    Left err -> do
      Logger.debug COMPILE_DEBUG ("Bridge: Compilation failed: " ++ show err)
      return (Left (Exit.BuildProjectProblem Exit.BP_CannotLoadDependencies))
    Right artifacts -> do
      -- Add dependency modules to artifacts
      let artifactsWithDeps = addDependencyModules artifacts depModules
      Logger.debug COMPILE_DEBUG "Bridge: Compilation succeeded"
      Logger.debug COMPILE_DEBUG ("Bridge: Total modules: " ++ show (length (Build._artifactsModules artifactsWithDeps)))
      return (Right artifactsWithDeps)

-- | Extract package name from Details.
extractPackageName :: Details.Details -> Pkg.Name
extractPackageName details =
  case Details._outline details of
    Details.ValidPkg pkg _ _ -> pkg
    Details.ValidApp _ -> Pkg.dummyName

-- | Extract project type from Details.
extractProjectType :: Details.Details -> Parse.ProjectType
extractProjectType details =
  case Details._outline details of
    Details.ValidPkg pkg _ _ -> Parse.Package pkg
    Details.ValidApp _ -> Parse.Application

-- | Load all interfaces from Details.
--
-- Returns both public interfaces (for compilation) and all dependency
-- interfaces (for code generation).
loadAllInterfacesFromDetails ::
  FilePath ->
  Details.Details ->
  IO (Map.Map ModuleName.Raw I.Interface, Map.Map ModuleName.Canonical I.DependencyInterface)
loadAllInterfacesFromDetails root details = do
  Logger.debug COMPILE_DEBUG "Bridge: Loading all interfaces from details"

  -- Use Details.loadInterfaces to get interface TVar
  interfacesTVar <- Details.loadInterfaces root details

  -- Read from TVar
  maybeDepInterfaces <- atomically (readTVar interfacesTVar)

  case maybeDepInterfaces of
    Nothing -> do
      Logger.debug COMPILE_DEBUG "Bridge: No interfaces loaded"
      return (Map.empty, Map.empty)
    Just depInterfaces -> do
      Logger.debug COMPILE_DEBUG ("Bridge: Loaded " ++ show (Map.size depInterfaces) ++ " dependency interfaces")

      -- Convert DependencyInterface to Interface, keeping only Public ones
      let interfaces = Map.mapMaybe extractPublicInterface depInterfaces
      Logger.debug COMPILE_DEBUG ("Bridge: Extracted " ++ show (Map.size interfaces) ++ " public interfaces")

      -- Convert from Canonical to Raw ModuleName (extract _module field)
      let rawInterfaces = Map.mapKeys canonicalToRaw interfaces

      -- Return both: public interfaces for compilation, all for code generation
      return (rawInterfaces, depInterfaces)

-- | Convert Canonical ModuleName to Raw.
canonicalToRaw :: ModuleName.Canonical -> ModuleName.Raw
canonicalToRaw (ModuleName.Canonical _ raw) = raw

-- | Extract public interface from dependency interface.
extractPublicInterface :: I.DependencyInterface -> Maybe I.Interface
extractPublicInterface (I.Public iface) = Just iface
extractPublicInterface (I.Private _ _ _) = Nothing

-- | Compile all paths and produce Build.Artifacts.
compileAllPaths ::
  Pkg.Name ->
  Map.Map ModuleName.Raw I.Interface ->
  Map.Map ModuleName.Canonical I.DependencyInterface ->
  Parse.ProjectType ->
  [FilePath] ->
  IO (Either Simple.QueryError Build.Artifacts)
compileAllPaths pkg ifaces depInterfaces projectType paths = do
  Logger.debug COMPILE_DEBUG ("Bridge: Compiling " ++ show (length paths) ++ " modules")

  case paths of
    [] -> do
      Logger.debug COMPILE_DEBUG "Bridge: No paths to compile"
      artifacts <- createEmptyArtifacts pkg depInterfaces
      return (Right artifacts)
    (firstPath : restPaths) -> do
      -- Compile first module
      firstResult <- Driver.compileModule pkg ifaces firstPath projectType

      case firstResult of
        Left err -> return (Left err)
        Right firstCompile -> do
          -- For now, compile only first module
          -- TODO: Compile remaining modules
          Logger.debug COMPILE_DEBUG "Bridge: Converting to Build.Artifacts"
          artifacts <- convertToArtifacts pkg depInterfaces [firstCompile] restPaths
          return (Right artifacts)

-- | Convert CompileResults to Build.Artifacts.
--
-- CRITICAL: Must include dependency interfaces in _artifactsDeps
-- for Generate to load all foreign code!
convertToArtifacts ::
  Pkg.Name ->
  Map.Map ModuleName.Canonical I.DependencyInterface ->
  [Driver.CompileResult] ->
  [FilePath] ->
  IO Build.Artifacts
convertToArtifacts pkg depInterfaces compileResults _restPaths = do
  Logger.debug COMPILE_DEBUG "Bridge: Converting compilation results to artifacts"

  -- Convert each CompileResult to a Build.Module
  let modules = map compileResultToModule compileResults

  -- Extract module names for roots
  let moduleNames = map extractModuleName compileResults
      roots = case moduleNames of
        [] -> NE.List (Build.Inside (Name.fromChars "Main")) []
        (first : rest) -> NE.List (Build.Inside first) (map Build.Inside rest)

  -- CRITICAL: Include dependency interfaces (this is what loads foreign code!)
  Logger.debug COMPILE_DEBUG ("Bridge: Including " ++ show (Map.size depInterfaces) ++ " dependency interfaces")

  -- Extract FFI info
  let ffiInfo = Map.empty -- TODO: Extract FFI info from compilation

  Logger.debug COMPILE_DEBUG ("Bridge: Created " ++ show (length modules) ++ " modules")

  return
    ( Build.Artifacts
        { Build._artifactsName = pkg,
          Build._artifactsDeps = depInterfaces,
          Build._artifactsRoots = roots,
          Build._artifactsModules = modules,
          Build._artifactsFFIInfo = ffiInfo
        }
    )

-- | Convert CompileResult to Build.Module.
compileResultToModule :: Driver.CompileResult -> Build.Module
compileResultToModule result =
  let canonModule = Driver.compileResultModule result
      iface = Driver.compileResultInterface result
      localGraph = Driver.compileResultLocalGraph result
      modName = extractModuleNameFromCanon canonModule
   in Build.Fresh modName iface localGraph

-- | Extract module name from CompileResult.
extractModuleName :: Driver.CompileResult -> ModuleName.Raw
extractModuleName result =
  extractModuleNameFromCanon (Driver.compileResultModule result)

-- | Extract module name from canonical module.
extractModuleNameFromCanon :: Can.Module -> ModuleName.Raw
extractModuleNameFromCanon (Can.Module name _ _ _ _ _ _ _) =
  case name of
    ModuleName.Canonical _ raw -> raw

-- | Create empty artifacts when no modules to compile.
createEmptyArtifacts ::
  Pkg.Name ->
  Map.Map ModuleName.Canonical I.DependencyInterface ->
  IO Build.Artifacts
createEmptyArtifacts pkg depInterfaces = do
  Logger.debug COMPILE_DEBUG "Bridge: Creating empty artifacts"

  let mainName = Name.fromChars "Main"
      emptyRoots = NE.List (Build.Inside mainName) []
      emptyModules = []
      emptyFFI = Map.empty

  return
    ( Build.Artifacts
        { Build._artifactsName = pkg,
          Build._artifactsDeps = depInterfaces,  -- Include dependency interfaces!
          Build._artifactsRoots = emptyRoots,
          Build._artifactsModules = emptyModules,
          Build._artifactsFFIInfo = emptyFFI
        }
    )

-- | Load dependency modules from GlobalGraph in Details.
--
-- This loads ALL pre-compiled dependency modules (elm/core, elm/html, etc.)
-- from the GlobalGraph stored in Details. These are essential for code
-- generation as they contain the actual implementations.
loadDependencyModules :: FilePath -> Details.Details -> IO [Build.Module]
loadDependencyModules root details = do
  Logger.debug COMPILE_DEBUG "Bridge: Loading dependency modules from GlobalGraph"

  -- Load the GlobalGraph (contains ALL dependency code)
  globalGraphTVar <- Details.loadObjects root details
  maybeGlobalGraph <- atomically (readTVar globalGraphTVar)

  -- Load the interfaces (needed for Build.Module)
  interfacesTVar <- Details.loadInterfaces root details
  maybeInterfaces <- atomically (readTVar interfacesTVar)

  case (maybeGlobalGraph, maybeInterfaces) of
    (Just globalGraph, Just interfaces) -> do
      -- Extract modules from GlobalGraph with their interfaces
      let modules = extractModulesFromGlobalGraph globalGraph interfaces
      Logger.debug COMPILE_DEBUG ("Bridge: Extracted " ++ show (length modules) ++ " modules from GlobalGraph")
      return modules
    _ -> do
      Logger.debug COMPILE_DEBUG "Bridge: No GlobalGraph or Interfaces available"
      return []

-- | Extract Build.Module entries from GlobalGraph.
--
-- The GlobalGraph contains optimized code for all dependencies.
-- We need to convert this into Build.Module format for inclusion
-- in the final artifacts.
extractModulesFromGlobalGraph ::
  Opt.GlobalGraph ->
  Map.Map ModuleName.Canonical I.DependencyInterface ->
  [Build.Module]
extractModulesFromGlobalGraph (Opt.GlobalGraph nodes _fields) interfaces =
  -- Group nodes by module name and convert to Build.Module
  Map.foldrWithKey (moduleGroupToModule interfaces) [] moduleGroups
  where
    moduleGroups = groupNodesByModule nodes

    groupNodesByModule :: Map.Map Opt.Global Opt.Node -> Map.Map ModuleName.Canonical (Map.Map Opt.Global Opt.Node)
    groupNodesByModule = Map.foldrWithKey addNodeToGroup Map.empty

    addNodeToGroup :: Opt.Global -> Opt.Node -> Map.Map ModuleName.Canonical (Map.Map Opt.Global Opt.Node) -> Map.Map ModuleName.Canonical (Map.Map Opt.Global Opt.Node)
    addNodeToGroup global@(Opt.Global modName _) node groups =
      Map.insertWith Map.union modName (Map.singleton global node) groups

    moduleGroupToModule ::
      Map.Map ModuleName.Canonical I.DependencyInterface ->
      ModuleName.Canonical ->
      Map.Map Opt.Global Opt.Node ->
      [Build.Module] ->
      [Build.Module]
    moduleGroupToModule ifaceMap canonName@(ModuleName.Canonical pkg modName) nodeMap modules =
      -- Create a LocalGraph for this module
      let localGraph = Opt.LocalGraph Nothing nodeMap Map.empty
          -- Extract interface from DependencyInterface
          maybeIface = extractInterface <$> Map.lookup canonName ifaceMap
          -- Create fallback empty interface if not found
          emptyIface = I.Interface pkg Map.empty Map.empty Map.empty Map.empty
          iface = maybe emptyIface id maybeIface
          module_ = Build.Fresh modName iface localGraph
      in module_ : modules

    -- Extract Interface from DependencyInterface
    extractInterface :: I.DependencyInterface -> I.Interface
    extractInterface (I.Public iface) = iface
    extractInterface (I.Private pkg unions aliases) =
      -- Private interfaces don't have values or binops, so create empty ones
      I.Interface pkg Map.empty (Map.map I.PrivateUnion unions) (Map.map I.PrivateAlias aliases) Map.empty

-- | Add dependency modules to artifacts.
--
-- Merges the newly compiled modules with the dependency modules
-- to create a complete artifact set for code generation.
addDependencyModules :: Build.Artifacts -> [Build.Module] -> Build.Artifacts
addDependencyModules artifacts depModules =
  artifacts { Build._artifactsModules = Build._artifactsModules artifacts ++ depModules }
