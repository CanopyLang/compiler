{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Root module validation for the Canopy build system.
--
-- This module provides functionality to validate the uniqueness and consistency
-- of root modules in a Canopy project. It ensures that root modules don't
-- conflict with each other or with internal project modules.
--
-- === Primary Functionality
--
-- * Root module uniqueness validation ('checkUniqueRoots')
-- * Name-path pair extraction from root statuses ('rootStatusToNamePathPair')
-- * Outside module duplicate detection ('checkOutside')
-- * Inside/outside module conflict detection ('checkInside')
--
-- === Validation Process
--
-- Root validation follows these steps:
--
-- 1. **Extract Outside Modules**: Convert root statuses to name-path pairs
-- 2. **Check Duplicates**: Validate no duplicate outside module names exist
-- 3. **Check Conflicts**: Ensure outside modules don't conflict with inside modules
-- 4. **Report Issues**: Return first problem found for user feedback
--
-- === Usage Examples
--
-- @
-- -- Basic root validation
-- case checkUniqueRoots insideStatuses outsideRoots of
--   Nothing -> putStrLn "All roots are unique"
--   Just problem -> handleRootProblem problem
--
-- -- Extract name-path pairs for processing
-- let pairs = Maybe.mapMaybe rootStatusToNamePathPair (NE.toList roots)
--     duplicates = Map.fromListWith OneOrMore.more pairs
-- @
--
-- === Root Status Types
--
-- Different root statuses are handled as follows:
--
-- * **@SInside@**: Internal project modules (ignored for outside validation)
-- * **@SOutsideOk@**: Successfully parsed outside modules (included)
-- * **@SOutsideErr@**: Failed outside modules (ignored to prevent cascading errors)
--
-- === Conflict Detection Rules
--
-- Conflicts occur when:
--
-- * Multiple outside modules have the same name but different file paths
-- * An outside module has the same name as an existing inside module
-- * Module name resolution becomes ambiguous
--
-- === Thread Safety
--
-- All functions are pure and thread-safe. The module uses immutable data
-- structures and functional error handling patterns.
--
-- @since 0.19.1
module Build.Validation.Roots
  ( -- * Root Validation
    checkUniqueRoots
  , rootStatusToNamePathPair
    -- * Conflict Detection
  , checkOutside
  , checkInside
  ) where

-- AST and module imports
import qualified AST.Source as Src
import qualified Canopy.Details as Details
import qualified Canopy.ModuleName as ModuleName

-- Build system imports
import Build.Types (Status (..), RootStatus (..))

-- Standard library imports
import Control.Lens ((^.))
import qualified Data.Foldable as Foldable
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.NonEmptyList as NE
import qualified Data.OneOrMore as OneOrMore
import qualified Reporting.Exit as Exit

-- | Validate uniqueness of root modules.
--
-- Ensures that root modules don't conflict with each other or with
-- internal project modules. Performs comprehensive validation of
-- both external roots and internal module conflicts.
--
-- ==== Validation Algorithm
--
-- 1. **Extract Outside Modules**: Convert successful outside root statuses
--    to name-path pairs for duplicate detection
-- 2. **Build Outside Dictionary**: Group paths by module name using OneOrMore
-- 3. **Check Outside Duplicates**: Validate each outside module name maps to
--    exactly one file path
-- 4. **Check Inside Conflicts**: Ensure outside modules don't conflict with
--    existing inside modules
--
-- ==== Error Reporting Strategy
--
-- Returns the first problem found to provide focused error messages:
--
-- * Outside duplicate problems are checked first
-- * Inside conflict problems are checked second
-- * Early termination prevents overwhelming error reports
--
-- ==== Performance Characteristics
--
-- * **Time Complexity**: O(n log n) where n = number of root modules
-- * **Space Complexity**: O(n) for intermediate data structures
-- * **Traversal Strategy**: Short-circuiting on first error found
--
-- @since 0.19.1
checkUniqueRoots :: Map.Map ModuleName.Raw Status -> NE.List RootStatus -> Maybe Exit.BuildProjectProblem
checkUniqueRoots insides sroots =
  let outsidesDict =
        Map.fromListWith OneOrMore.more (Maybe.mapMaybe rootStatusToNamePathPair (NE.toList sroots))
   in case Map.traverseWithKey checkOutside outsidesDict of
        Left problem ->
          Just problem
        Right outsides ->
          case Foldable.sequenceA_ (Map.intersectionWithKey checkInside outsides insides) of
            Right () -> Nothing
            Left problem -> Just problem

-- | Extract name and path from root status.
--
-- Converts root status information into name-path pairs for duplicate
-- detection and conflict resolution. Only successful outside roots
-- contribute to the validation process.
--
-- ==== Root Status Processing
--
-- * **@SInside@**: Internal modules - returns @Nothing@ (not outside root)
-- * **@SOutsideOk@**: Successful outside parse - returns @Just (name, path)@
-- * **@SOutsideErr@**: Failed outside parse - returns @Nothing@ (ignore errors)
--
-- ==== Path Extraction
--
-- For successful outside modules, extracts:
--
-- * **Module Name**: From parsed module structure (@Src.getName modul@)
-- * **File Path**: From local details (@local ^. Details.path@)
-- * **OneOrMore Wrapper**: Enables automatic duplicate aggregation
--
-- @since 0.19.1
rootStatusToNamePathPair :: RootStatus -> Maybe (ModuleName.Raw, OneOrMore.OneOrMore FilePath)
rootStatusToNamePathPair sroot =
  case sroot of
    SInside _ -> Nothing
    SOutsideOk local _ modul -> Just (Src.getName modul, OneOrMore.one (local ^. Details.path))
    SOutsideErr _ -> Nothing

-- | Check for duplicate outside module names.
--
-- Validates that each outside module name corresponds to exactly one
-- file path. Multiple paths for the same module name indicate an
-- ambiguous build configuration that must be resolved.
--
-- ==== Duplicate Detection
--
-- Uses OneOrMore structure to detect duplicates:
--
-- * **Single Path**: @OneOrMore.destruct@ returns @NE.List p []@ - valid
-- * **Multiple Paths**: @OneOrMore.destruct@ returns @NE.List p1 (p2 : _)@ - duplicate
--
-- ==== Error Construction
--
-- For duplicates, creates @BP_RootNameDuplicate@ error with:
--
-- * **Module Name**: The conflicting module name
-- * **First Path**: Primary file path found
-- * **Second Path**: Conflicting file path found
--
-- @since 0.19.1
checkOutside :: ModuleName.Raw -> OneOrMore.OneOrMore FilePath -> Either Exit.BuildProjectProblem FilePath
checkOutside name paths =
  case OneOrMore.destruct NE.List paths of
    NE.List p [] -> Right p
    NE.List p1 (p2 : _) -> Left (Exit.BP_RootNameDuplicate name p1 p2)

-- | Check for conflicts between outside and inside modules.
--
-- Validates that outside root modules don't conflict with modules
-- that are already part of the internal project structure. Prevents
-- ambiguous module resolution.
--
-- ==== Conflict Detection Rules
--
-- Conflicts occur when outside modules have the same name as:
--
-- * **@SCached@ modules**: Cached internal modules
-- * **@SChanged@ modules**: Modified internal modules
--
-- Non-conflicting inside statuses:
--
-- * **@SBadImport@**: Import errors don't cause conflicts
-- * **@SBadSyntax@**: Syntax errors don't cause conflicts  
-- * **@SForeign@**: Foreign modules don't cause conflicts
-- * **@SKernel@**: Kernel modules don't cause conflicts
--
-- ==== Error Reporting
--
-- For conflicts, creates @BP_RootNameDuplicate@ error with:
--
-- * **Module Name**: The conflicting module name
-- * **Outside Path**: The outside module file path
-- * **Inside Path**: The inside module file path
--
-- @since 0.19.1
checkInside :: ModuleName.Raw -> FilePath -> Status -> Either Exit.BuildProjectProblem ()
checkInside name p1 status =
  case status of
    SCached local -> Left (Exit.BP_RootNameDuplicate name p1 (local ^. Details.path))
    SChanged local _ _ _ -> Left (Exit.BP_RootNameDuplicate name p1 (local ^. Details.path))
    SBadImport _ -> Right ()
    SBadSyntax {} -> Right ()
    SForeign _ -> Right ()
    SKernel -> Right ()