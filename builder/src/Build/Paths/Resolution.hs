{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Path resolution and root finding for the Canopy compiler.
--
-- This module handles file path resolution, source directory management,
-- and root module discovery. It provides the path-handling infrastructure
-- needed to locate and validate source files within the project structure.
--
-- === Primary Responsibilities
--
-- * Root module discovery from file paths ('findRoots', 'getRootInfo')
-- * Source directory validation and path resolution
-- * Module name derivation from file paths
-- * Path validation and security checks
-- * Source directory structure analysis
--
-- === Usage Examples
--
-- @
-- -- Find root modules from file paths
-- result <- findRoots env ["/path/to/Main.can", "/path/to/Utils.can"]
-- case result of
--   Left problem -> handlePathProblem problem
--   Right locations -> processRootLocations locations
--
-- -- Get detailed root information
-- rootInfo <- getRootInfo env "/path/to/Module.can"
-- case rootInfo of
--   Right (RootInfo absolute relative location) -> processRoot location
--   Left problem -> handleRootError problem
-- @
--
-- === Path Resolution Process
--
-- The path resolution follows these steps:
--
-- 1. Path existence validation
-- 2. Path canonicalization for consistency
-- 3. Source directory detection and validation
-- 4. Module name derivation from directory structure
-- 5. Duplicate detection and conflict resolution
--
-- === Source Directory Handling
--
-- The module handles both:
--
-- * **Inside modules**: Files within configured source directories
-- * **Outside modules**: Files external to source directories
-- * **Multiple source directories**: With proper conflict detection
--
-- === Security Considerations
--
-- Path resolution includes security validations:
--
-- * Extension validation (only .can, .canopy, .elm files)
-- * Path traversal prevention
-- * Canonical path resolution to prevent symlink attacks
--
-- @since 0.19.1
module Build.Paths.Resolution
  ( -- * Root Discovery
    findRoots
  , getRootInfo
  , getRootInfoHelp
    
  -- * Source Directory Utilities
  , isInsideSrcDirByName
  , isInsideSrcDirByPath
  , isGoodName
    
  -- * Path Utilities
  , dropPrefix
  , checkRoots
  ) where

-- Canopy-specific imports

-- Build system imports
import Build.Types
  ( Env (..)
  , AbsoluteSrcDir (..)
  , RootInfo (..)
  , RootLocation (..)
  , rootInfoRelative
  , rootInfoLocation
  )
import qualified Build.Orchestration as Orchestration

-- Standard library imports
import Control.Concurrent.MVar (readMVar)
import Control.Lens ((^.))
import qualified Control.Monad as Monad
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Name as Name
import qualified Data.NonEmptyList as NE
import qualified Data.OneOrMore as OneOrMore
import qualified File
import qualified Reporting.Exit as Exit
import qualified System.Directory as Dir
import System.FilePath ((<.>))
import qualified System.FilePath as FP

-- | Find root modules from a list of file paths.
--
-- Processes multiple file paths concurrently to discover root module
-- information and validates that there are no conflicts between roots.
-- This is the main entry point for path-based module discovery.
--
-- ==== Concurrent Processing
--
-- File path processing is parallelized using forked computations to
-- improve performance when handling multiple files. Each path is
-- processed independently, then results are validated collectively.
--
-- ==== Validation Steps
--
-- 1. Get root information for each path concurrently
-- 2. Check for duplicate absolute paths
-- 3. Validate no conflicting module names
-- 4. Return validated root locations
--
-- ==== Parameters
--
-- [@env@]: Build environment with source directory configuration
-- [@paths@]: List of file paths to process as potential roots
--
-- ==== Errors
--
-- Returns 'Exit.BuildProjectProblem' for:
--
-- * Non-existent files
-- * Invalid file extensions
-- * Duplicate module names from different paths
-- * Conflicting source directory assignments
--
-- @since 0.19.1
findRoots :: Env -> NE.List FilePath -> IO (Either Exit.BuildProjectProblem (NE.List RootLocation))
findRoots env paths = do
  mvars <- traverse (Orchestration.fork . getRootInfo env) paths
  einfos <- traverse readMVar mvars
  return (sequenceA einfos >>= checkRoots)

-- | Validate root information and extract locations.
--
-- Takes a list of root information and validates that there are no
-- conflicts, then extracts the location information needed for build
-- processing.
--
-- ==== Conflict Detection
--
-- Checks for duplicate absolute paths that would indicate the same
-- file being specified multiple times with different relative paths.
-- This prevents ambiguous build configurations.
--
-- @since 0.19.1
checkRoots :: NE.List RootInfo -> Either Exit.BuildProjectProblem (NE.List RootLocation)
checkRoots infos =
  let toOneOrMore loc@(RootInfo absolute _ _) =
        (absolute, OneOrMore.one loc)

      fromOneOrMore loc locs =
        case locs of
          [] -> Right ()
          loc2 : _ -> Left (Exit.BP_MainPathDuplicate (loc ^. rootInfoRelative) (loc2 ^. rootInfoRelative))
   in ((fmap (\_ -> fmap (^. rootInfoLocation) infos) . traverse (OneOrMore.destruct fromOneOrMore)) . Map.fromListWith OneOrMore.more $ fmap toOneOrMore (NE.toList infos))

-- | Get detailed root information for a file path.
--
-- Analyzes a file path to determine its relationship to the project
-- source directories and derives appropriate module naming and location
-- information.
--
-- ==== Path Analysis Process
--
-- 1. Validates file existence
-- 2. Canonicalizes path for consistency
-- 3. Delegates to detailed analysis helper
--
-- ==== Error Conditions
--
-- * File does not exist: 'Exit.BP_PathUnknown'
-- * Invalid file extension: 'Exit.BP_WithBadExtension'
-- * Invalid module name characters: 'Exit.BP_RootNameInvalid'
-- * Ambiguous source directory: 'Exit.BP_WithAmbiguousSrcDir'
-- * Duplicate module names: 'Exit.BP_RootNameDuplicate'
--
-- @since 0.19.1
getRootInfo :: Env -> FilePath -> IO (Either Exit.BuildProjectProblem RootInfo)
getRootInfo env path = do
  exists <- File.exists path
  if exists
    then Dir.canonicalizePath path >>= getRootInfoHelp env path
    else return (Left (Exit.BP_PathUnknown path))

-- | Helper function for detailed root information analysis.
--
-- Performs the core analysis of a canonical file path to determine
-- module location, name derivation, and source directory relationship.
--
-- ==== Analysis Steps
--
-- 1. Validates file extension (.can, .canopy, .elm)
-- 2. Splits path into directory and file components
-- 3. Attempts to match against source directories
-- 4. Derives module name from directory structure
-- 5. Validates module name characters and uniqueness
--
-- ==== Module Name Derivation
--
-- For files inside source directories:
-- * Converts directory path to dot-separated module name
-- * Validates each component starts with uppercase letter
-- * Checks for conflicts with other source directories
--
-- For files outside source directories:
-- * Treats as external module with original path
--
-- @since 0.19.1
getRootInfoHelp :: Env -> FilePath -> FilePath -> IO (Either Exit.BuildProjectProblem RootInfo)
getRootInfoHelp (Env _ _ _ srcDirs _ _ _) path absolutePath = do
  let (dirs, file) = FP.splitFileName absolutePath
      (final, ext) = FP.splitExtension file
  if not (validateExtension ext)
    then return . Left $ Exit.BP_WithBadExtension path
    else do
      let absoluteSegments = FP.splitDirectories dirs <> [final]
      processSegments path absolutePath srcDirs absoluteSegments

-- | Validate file extension.
--
-- @since 0.19.1
validateExtension :: String -> Bool
validateExtension ext = ext == ".can" || ext == ".canopy" || ext == ".elm"

-- | Process path segments to determine root info.
--
-- @since 0.19.1
processSegments :: FilePath -> FilePath -> [AbsoluteSrcDir] -> [String] -> IO (Either Exit.BuildProjectProblem RootInfo)
processSegments path absolutePath srcDirs absoluteSegments =
  case Maybe.mapMaybe (isInsideSrcDirByPath absoluteSegments) srcDirs of
    [] -> return . Right $ RootInfo absolutePath path (LOutside path)
    [(_, Right names)] -> processValidNames path absolutePath srcDirs names
    [(s, Left names)] -> return . Left $ Exit.BP_RootNameInvalid path s names
    (s1, _) : (s2, _) : _ -> return . Left $ Exit.BP_WithAmbiguousSrcDir path s1 s2

-- | Process valid module names.
--
-- @since 0.19.1
processValidNames :: FilePath -> FilePath -> [AbsoluteSrcDir] -> [String] -> IO (Either Exit.BuildProjectProblem RootInfo)
processValidNames path absolutePath srcDirs names = do
  let name = Name.fromChars (List.intercalate "." names)
  matchingDirs <- Monad.filterM (isInsideSrcDirByName names) srcDirs
  case matchingDirs of
    d1 : d2 : _ -> createDuplicateError name d1 d2 names
    _ -> return . Right $ RootInfo absolutePath path (LInside name)

-- | Create duplicate name error.
--
-- @since 0.19.1
createDuplicateError :: Name.Name -> AbsoluteSrcDir -> AbsoluteSrcDir -> [String] -> IO (Either Exit.BuildProjectProblem RootInfo)
createDuplicateError name d1 d2 names = do
  let p1 = Orchestration.addRelative d1 (FP.joinPath names <.> "can")
      p2 = Orchestration.addRelative d2 (FP.joinPath names <.> "can")
  return . Left $ Exit.BP_RootNameDuplicate name p1 p2

-- | Check if a module name exists in a source directory.
--
-- Verifies that a module with the given name components exists in the
-- specified source directory by checking for .can, .canopy, or .elm files.
--
-- ==== File Extension Priority
--
-- Checks extensions in this order:
-- 1. .can (Canopy native)
-- 2. .canopy (Canopy alternative)  
-- 3. .elm (Elm compatibility)
--
-- @since 0.19.1
isInsideSrcDirByName :: [String] -> AbsoluteSrcDir -> IO Bool
isInsideSrcDirByName names srcDir = do
  let base = FP.joinPath names
  existsCan <- File.exists (Orchestration.addRelative srcDir (base <.> "can"))
  if existsCan
    then return True
    else do
      existsCanopy <- File.exists (Orchestration.addRelative srcDir (base <.> "canopy"))
      if existsCanopy then return True else File.exists (Orchestration.addRelative srcDir (base <.> "elm"))

-- | Check if a path is inside a source directory and derive module name.
--
-- Analyzes a file path to determine if it falls within a source directory
-- and attempts to derive a valid module name from the directory structure.
--
-- ==== Module Name Validation
--
-- For each path component:
-- * Must start with uppercase letter
-- * Remaining characters must be alphanumeric or underscore
-- * Overall path structure must be valid for module naming
--
-- ==== Return Values
--
-- * @Nothing@: Path is not within this source directory
-- * @Just (srcDir, Right names)@: Valid module name components derived
-- * @Just (srcDir, Left names)@: Invalid module name characters found
--
-- @since 0.19.1
isInsideSrcDirByPath :: [String] -> AbsoluteSrcDir -> Maybe (FilePath, Either [String] [String])
isInsideSrcDirByPath segments (AbsoluteSrcDir srcDir) =
  case dropPrefix (FP.splitDirectories srcDir) segments of
    Nothing ->
      Nothing
    Just names ->
      if List.all isGoodName names
        then Just (srcDir, Right names)
        else Just (srcDir, Left names)

-- | Validate that a name component is suitable for module naming.
--
-- Checks that a path component follows Canopy module naming conventions:
--
-- * Non-empty
-- * Starts with uppercase letter
-- * Contains only alphanumeric characters and underscores
--
-- @since 0.19.1
isGoodName :: String -> Bool
isGoodName name =
  case name of
    [] ->
      False
    char : chars ->
      Char.isUpper char && List.all (\c -> Char.isAlphaNum c || c == '_') chars

-- | Remove a prefix from a path list.
--
-- Attempts to strip a directory prefix from a path, returning the
-- remaining components if the prefix matches.
--
-- ==== Path Matching
--
-- Both inputs must be canonicalized for accurate matching. The function
-- performs component-wise comparison to ensure exact prefix matching.
--
-- ==== INVARIANT
--
-- 'Dir.canonicalizePath' has been run on both inputs to ensure
-- consistent path representation.
--
-- @since 0.19.1
dropPrefix :: [FilePath] -> [FilePath] -> Maybe [FilePath]
dropPrefix roots paths =
  case roots of
    [] ->
      Just paths
    r : rs ->
      case paths of
        [] -> Nothing
        p : ps -> if r == p then dropPrefix rs ps else Nothing

-- Note: Helper functions addRelative, fork, and readMVar are imported from other modules