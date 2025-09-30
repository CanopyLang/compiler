{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall -fno-warn-unused-do-bind #-}

-- | Core compilation pipeline for Canopy modules.
--
-- This module orchestrates the complete compilation process from source AST
-- to optimized artifacts. It coordinates multiple compilation phases including
-- canonicalization, type checking, pattern match validation, and optimization.
--
-- == Compilation Pipeline
--
-- The compilation process follows these sequential phases:
--
-- 1. **Canonicalization** - Resolve names and validate module structure
-- 2. **Type Checking** - Infer and validate types with constraint solving
-- 3. **Pattern Validation** - Ensure exhaustive pattern match coverage
-- 4. **Optimization** - Generate optimized intermediate representation
--
-- == Usage Examples
--
-- @
-- import qualified Compile
-- import qualified Canopy.Package as Pkg
-- import qualified AST.Source as Src
--
-- -- Compile a source module
-- compileModule :: Pkg.Name -> Interfaces -> Src.Module -> Either Error Artifacts
-- compileModule pkg ifaces sourceModule =
--   Compile.compile pkg ifaces sourceModule
-- @
--
-- == Error Handling
--
-- All compilation phases use 'Either' for error propagation with rich error types:
--   * 'E.BadNames' - Canonicalization failures (undefined names, scope errors)
--   * 'E.BadTypes' - Type checking failures (type mismatches, constraint violations)
--   * 'E.BadPatterns' - Pattern match failures (non-exhaustive patterns)
--   * 'E.BadMains' - Optimization failures (invalid main functions)
--
-- @since 0.19.1
module Compile
  ( -- * Core Types
    Artifacts (..),

    -- * Compilation Interface
    compile,
    compileWithRoot,

    -- * Lens Accessors
    artifactsModule,
    artifactsTypes,
    artifactsGraph,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified AST.Source as Src
import qualified Canonicalize.Module as Canonicalize
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Lens (Lens')
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Foreign.FFI as FFI
import qualified Generate.JavaScript as JS
import qualified Nitpick.PatternMatches as PatternMatches
import qualified Optimize.Module as Optimize
import qualified Reporting.Annotation as A
import qualified Reporting.Error as E
import qualified Reporting.Error.Syntax as Syntax
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Reporting.Result as R
-- import System.IO.Unsafe (unsafePerformIO) -- No longer needed - fixed MVar deadlock by using IO properly
import qualified Type.Constrain.Module as Type
import qualified Type.Solve as Type

-- New compiler integration
import qualified New.Compiler.Driver as Driver
import qualified New.Compiler.Debug.Logger as Logger
import New.Compiler.Debug.Logger (DebugCategory (..))
import qualified New.Compiler.Query.Simple as Simple
import qualified System.Environment as Env

-- | Compilation artifacts containing all outputs from the compilation pipeline.
--
-- The 'Artifacts' type encapsulates the complete result of successfully compiling
-- a source module through all compilation phases. Each field represents the output
-- of a specific compilation stage.
--
-- == Field Documentation
--
-- * '_artifactsModule' - Canonicalized AST with resolved names and validated structure
-- * '_artifactsTypes' - Type annotations for all definitions in the module
-- * '_artifactsGraph' - Optimized local dependency graph for code generation
--
-- == Usage Examples
--
-- @
-- import Control.Lens ((^.))
--
-- -- Access compilation artifacts using lenses
-- processArtifacts :: Artifacts -> IO ()
-- processArtifacts artifacts = do
--   let canonical = artifacts ^. artifactsModule
--       typeMap = artifacts ^. artifactsTypes
--       optimized = artifacts ^. artifactsGraph
--   -- Process each artifact...
-- @
--
-- @since 0.19.1
data Artifacts = Artifacts
  { _artifactsModule :: !Can.Module,
    _artifactsTypes :: !(Map Name.Name Can.Annotation),
    _artifactsGraph :: !Opt.LocalGraph,
    _artifactsFFIInfo :: !(Map String JS.FFIInfo)
  }

-- | Lens accessors for Artifacts record fields.
--
-- Only creates lenses for the fields that are actually used to avoid
-- compiler warnings about unused bindings.
--
-- @since 0.19.1
artifactsModule :: Lens' Artifacts Can.Module
artifactsModule f artifacts = fmap (\m -> artifacts { _artifactsModule = m }) (f (_artifactsModule artifacts))

artifactsTypes :: Lens' Artifacts (Map Name.Name Can.Annotation)
artifactsTypes f artifacts = fmap (\t -> artifacts { _artifactsTypes = t }) (f (_artifactsTypes artifacts))

artifactsGraph :: Lens' Artifacts Opt.LocalGraph
artifactsGraph f artifacts = fmap (\g -> artifacts { _artifactsGraph = g }) (f (_artifactsGraph artifacts))

-- | Compile a source module through the complete compilation pipeline.
--
-- Orchestrates all compilation phases in sequence, ensuring each phase
-- completes successfully before proceeding to the next. The compilation
-- process is pure and deterministic - the same input will always produce
-- the same output or the same error.
--
-- == Compilation Phases
--
-- 1. **Canonicalization** - Resolves names, validates imports, and creates canonical AST
-- 2. **Type Checking** - Infers types and validates type constraints
-- 3. **Pattern Validation** - Ensures pattern matches are exhaustive and non-redundant
-- 4. **Optimization** - Generates optimized intermediate representation
--
-- == Examples
--
-- >>> import qualified Canopy.Package as Pkg
-- >>> import qualified Data.Map as Map
-- >>> compile Pkg.core Map.empty sourceModule
-- Right (Artifacts {...})
--
-- >>> compile invalidPkg interfaces malformedModule
-- Left (E.BadNames [...])
--
-- == Error Conditions
--
-- Returns 'Left' with specific error types for each phase:
--   * 'E.BadNames' - Undefined variables, invalid imports, scope violations
--   * 'E.BadTypes' - Type mismatches, constraint failures, infinite types
--   * 'E.BadPatterns' - Non-exhaustive patterns, redundant patterns
--   * 'E.BadMains' - Invalid main function, optimization failures
--
-- @since 0.19.1
compile ::
  -- | Package name for the module being compiled
  Pkg.Name ->
  -- | Available module interfaces for dependency resolution
  Map ModuleName.Raw I.Interface ->
  -- | Source module to compile
  Src.Module ->
  -- | Compilation artifacts or error (now in IO monad for thread safety)
  IO (Either E.Error Artifacts)
compile pkg ifaces modul = do
  -- Check if we should use new compiler
  useNew <- shouldUseNewCompiler
  if useNew
    then compileWithNewCompiler pkg ifaces modul
    else compileWithOldCompiler pkg ifaces modul

-- | Check if new compiler should be used.
shouldUseNewCompiler :: IO Bool
shouldUseNewCompiler = do
  maybeFlag <- Env.lookupEnv "CANOPY_NEW_COMPILER"
  return (maybeFlag == Just "1")

-- | Compile with new query-based compiler.
compileWithNewCompiler ::
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  Src.Module ->
  IO (Either E.Error Artifacts)
compileWithNewCompiler pkg ifaces modul = do
  Logger.debug COMPILE_DEBUG "[Compile.hs] Using new query-based compiler"

  result <- Driver.compileFromSource pkg ifaces modul

  case result of
    Left queryErr -> convertQueryError queryErr
    Right compileResult -> convertToArtifacts compileResult

-- | Convert query error to old error format.
convertQueryError :: Simple.QueryError -> IO (Either E.Error a)
convertQueryError err = do
  Logger.debug COMPILE_DEBUG ("[Compile.hs] Query error: " ++ show err)
  -- TODO: Proper error conversion
  return (Left (E.BadSyntax (Syntax.ModuleNameUnspecified "Unknown")))

-- | Convert CompileResult to Artifacts.
convertToArtifacts ::
  Driver.CompileResult ->
  IO (Either E.Error Artifacts)
convertToArtifacts result = do
  Logger.debug COMPILE_DEBUG "[Compile.hs] Converting CompileResult to Artifacts"

  let canonModule = Driver.compileResultModule result
      types = Driver.compileResultTypes result
      localGraph = Driver.compileResultLocalGraph result
      ffiInfo = Map.empty  -- TODO: Extract FFI info

  return (Right (Artifacts canonModule types localGraph ffiInfo))

-- | Compile with old compiler (original implementation).
compileWithOldCompiler ::
  Pkg.Name ->
  Map ModuleName.Raw I.Interface ->
  Src.Module ->
  IO (Either E.Error Artifacts)
compileWithOldCompiler pkg ifaces modul@(Src.Module _ _ _ _ foreignImports _ _ _ _ _) = do
  -- DEBUG: Add detailed logging to track compilation progress
  putStrLn ("COMPILE-INTERNAL: Starting compilation for pkg " <> show pkg)
  putStrLn ("COMPILE-INTERNAL: Module has " <> show (length foreignImports) <> " foreign imports")

  -- CRITICAL: Load FFI content in IO monad BEFORE pure compilation phases
  -- This eliminates the unsafePerformIO MVar deadlock that was causing
  -- "thread blocked indefinitely in an MVar operation" errors
  putStrLn ("COMPILE-INTERNAL: About to load FFI content")
  ffiContentMap <- Canonicalize.loadFFIContent foreignImports
  putStrLn ("COMPILE-INTERNAL: FFI content loaded, " <> show (Map.size ffiContentMap) <> " items")

  -- Convert FFI content map to FFI info format
  let ffiInfoMap = convertFFIContentToInfo foreignImports ffiContentMap
  putStrLn ("COMPILE-INTERNAL: FFI info map created, " <> show (Map.size ffiInfoMap) <> " items")

  -- Now perform compilation phases with pre-loaded FFI content
  -- Note: typeCheck is now in IO to prevent MVar deadlocks
  putStrLn ("COMPILE-INTERNAL: About to canonicalize")
  case canonicalizePure pkg ifaces ffiContentMap modul of
    Left canonError -> do
      putStrLn ("COMPILE-INTERNAL: Canonicalization failed: " <> show canonError)
      pure (Left canonError)
    Right canonical -> do
      putStrLn ("COMPILE-INTERNAL: Canonicalization successful, about to type check")
      typeResult <- typeCheck modul canonical
      putStrLn ("COMPILE-INTERNAL: Type check completed")
      case typeResult of
        Left typeError -> do
          putStrLn ("COMPILE-INTERNAL: Type check failed: " <> show typeError)
          pure (Left typeError)
        Right annotations -> do
          putStrLn ("COMPILE-INTERNAL: Type check successful, about to nitpick")
          case nitpick canonical of
            Left nitpickError -> do
              putStrLn ("COMPILE-INTERNAL: Nitpick failed: " <> show nitpickError)
              pure (Left nitpickError)
            Right () -> do
              putStrLn ("COMPILE-INTERNAL: Nitpick successful, about to optimize")
              case optimize modul annotations canonical of
                Left optimizeError -> do
                  putStrLn ("COMPILE-INTERNAL: Optimization failed: " <> show optimizeError)
                  pure (Left optimizeError)
                Right objects -> do
                  putStrLn ("COMPILE-INTERNAL: Optimization successful, creating artifacts")
                  pure (Right (Artifacts canonical annotations objects ffiInfoMap))

-- | Compile a module with explicit root directory for FFI path resolution.
--
-- This variant of 'compile' allows passing the project root directory
-- to properly resolve relative paths in foreign import statements.
-- This fixes MVar deadlocks that occurred when FFI files couldn't be found.
--
-- @since 0.19.1
compileWithRoot ::
  -- | Package name for the module being compiled
  Pkg.Name ->
  -- | Available module interfaces for dependency resolution
  Map ModuleName.Raw I.Interface ->
  -- | Project root directory for path resolution
  FilePath ->
  -- | Source module to compile
  Src.Module ->
  -- | Compilation artifacts or error (now in IO monad for thread safety)
  IO (Either E.Error Artifacts)
compileWithRoot pkg ifaces rootDir modul@(Src.Module _ _ _ _ foreignImports _ _ _ _ _) = do
  -- CRITICAL: Load FFI content with proper root directory path resolution
  -- This eliminates path resolution issues that caused MVar deadlocks
  ffiContentMap <- Canonicalize.loadFFIContentWithRoot rootDir foreignImports

  -- Convert FFI content map to FFI info format
  let ffiInfoMap = convertFFIContentToInfo foreignImports ffiContentMap

  -- Now perform compilation phases with pre-loaded FFI content
  -- Note: typeCheck is now in IO to prevent MVar deadlocks
  case canonicalizePure pkg ifaces ffiContentMap modul of
    Left canonError -> pure (Left canonError)
    Right canonical -> do
      typeResult <- typeCheck modul canonical
      case typeResult of
        Left typeError -> pure (Left typeError)
        Right annotations ->
          case nitpick canonical of
            Left nitpickError -> pure (Left nitpickError)
            Right () ->
              case optimize modul annotations canonical of
                Left optimizeError -> pure (Left optimizeError)
                Right objects -> pure (Right (Artifacts canonical annotations objects ffiInfoMap))

-- COMPILATION PHASES
--
-- Each phase represents a distinct transformation in the compilation pipeline.
-- Phases are kept as internal functions to maintain clean separation of concerns
-- while providing focused error handling for each compilation stage.

-- | Transform source AST to canonical AST with resolved names.
--
-- Canonicalization resolves all names to their definitions, validates import
-- statements, and ensures all referenced symbols are available. This phase
-- catches undefined variable errors and import-related issues.
--
-- == Process
--
-- 1. Resolve all name references to their definitions
-- 2. Validate import statements and exposed symbols
-- 3. Build canonical AST with fully qualified names
-- 4. Detect circular dependencies and scope violations
--
-- == Error Cases
--
-- * Undefined variables or functions
-- * Invalid import statements
-- * Circular module dependencies
-- * Name shadowing violations
-- * Scope resolution failures
--
-- @since 0.19.1

-- | Canonicalize a source module with thread-safe FFI handling
--
-- This function now performs FFI file loading and canonicalization in the
-- Result monad to avoid threading issues. The old signature is maintained
-- for compatibility with the existing compilation pipeline.
--
-- @since 0.19.1
-- | Canonicalize a source module with pre-loaded FFI content (pure)
--
-- This function performs canonicalization using pre-loaded FFI content
-- to avoid any IO operations or threading issues. The FFI content should
-- be loaded in the IO monad before calling this function.
--
-- @since 0.19.1
canonicalizePure ::
  -- | Package context for name resolution
  Pkg.Name ->
  -- | Available module interfaces
  Map ModuleName.Raw I.Interface ->
  -- | Pre-loaded FFI content map
  Map String String ->
  -- | Source module to canonicalize
  Src.Module ->
  -- | Canonical module or canonicalization errors
  Either E.Error Can.Module
canonicalizePure pkg ifaces ffiContentMap modul =
  case snd . R.run $ Canonicalize.canonicalize pkg ifaces ffiContentMap modul of
    Right canonical -> Right canonical
    Left errors -> Left $ E.BadNames errors

-- | Perform type inference and checking on canonical AST.
--
-- Type checking generates type constraints from the canonical AST and solves
-- them to produce type annotations for all definitions. This phase catches
-- type errors, constraint violations, and ensures type safety.
--
-- == Process
--
-- 1. Generate type constraints from canonical AST expressions
-- 2. Solve constraint system using unification and subtyping
-- 3. Produce type annotations mapping names to their inferred types
-- 4. Validate type correctness and detect infinite types
--
-- == Error Cases
--
-- * Type mismatches between expected and actual types
-- * Unsolvable type constraints
-- * Infinite or recursive type definitions
-- * Missing type class instances
-- * Constraint solver failures
--
-- @since 0.19.1
typeCheck ::
  -- | Original source module for error localization
  Src.Module ->
  -- | Canonical module to type check
  Can.Module ->
  -- | Type annotations or type errors (now in IO monad for thread safety)
  IO (Either E.Error (Map Name.Name Can.Annotation))
typeCheck modul canonical = do
  -- FIXED: Now properly running in IO monad instead of unsafePerformIO
  -- This eliminates the MVar deadlock issues during concurrent compilation
  constraintResult <- Type.constrain canonical >>= Type.run
  case constraintResult of
    Right annotations -> pure (Right annotations)
    Left errors -> pure (Left (E.BadTypes (Localizer.fromModule modul) errors))

-- | Validate pattern match exhaustiveness and detect redundant patterns.
--
-- Pattern validation ensures that all pattern matches are exhaustive (cover
-- all possible cases) and contain no redundant or unreachable patterns. This
-- prevents runtime pattern match failures and warns about dead code.
--
-- == Process
--
-- 1. Analyze all pattern matches in the canonical AST
-- 2. Check exhaustiveness using decision tree construction
-- 3. Detect redundant or unreachable patterns
-- 4. Validate guard conditions and boolean patterns
--
-- == Error Cases
--
-- * Non-exhaustive pattern matches (missing cases)
-- * Redundant patterns that will never be reached
-- * Overlapping patterns with same precedence
-- * Invalid guard conditions in patterns
--
-- @since 0.19.1
nitpick ::
  -- | Canonical module to validate patterns in
  Can.Module ->
  -- | Success or pattern match errors
  Either E.Error ()
nitpick canonical =
  case PatternMatches.check canonical of
    Right () -> Right ()
    Left errors -> Left (E.BadPatterns errors)

-- | Generate optimized intermediate representation for code generation.
--
-- Optimization transforms the canonical AST into an optimized local dependency
-- graph suitable for efficient code generation. This phase performs various
-- optimizations while preserving semantic correctness.
--
-- == Process
--
-- 1. Transform canonical AST to optimized intermediate representation
-- 2. Apply dead code elimination and inlining optimizations
-- 3. Build local dependency graph for efficient code generation
-- 4. Validate main function signatures and entry points
--
-- == Error Cases
--
-- * Invalid main function signatures
-- * Optimization failures that break semantics
-- * Circular dependencies in optimization graph
-- * Code generation preparation failures
--
-- @since 0.19.1
optimize ::
  -- | Original source module for error localization
  Src.Module ->
  -- | Type annotations from type checking phase
  Map Name.Name Can.Annotation ->
  -- | Canonical module to optimize
  Can.Module ->
  -- | Optimized dependency graph or optimization errors
  Either E.Error Opt.LocalGraph
optimize modul annotations canonical =
  case snd . R.run $ Optimize.optimize annotations canonical of
    Right localGraph -> Right localGraph
    Left errors -> Left (E.BadMains (Localizer.fromModule modul) errors)

-- | Convert FFI content map to FFI info format
--
-- This function takes the FFI content loaded during canonicalization and
-- combines it with foreign import information to create the FFI info format
-- needed for JavaScript generation.
--
-- @since 0.19.1
convertFFIContentToInfo :: [Src.ForeignImport] -> Map String String -> Map String JS.FFIInfo
convertFFIContentToInfo foreignImports ffiContentMap =
  Map.fromList $ concatMap convertSingleImport foreignImports
  where
    convertSingleImport :: Src.ForeignImport -> [(String, JS.FFIInfo)]
    convertSingleImport (Src.ForeignImport target alias _region) =
      case target of
        FFI.JavaScriptFFI jsPath ->
          case Map.lookup jsPath ffiContentMap of
            Just content ->
              let aliasStr = Name.toChars (A.toValue alias)
                  ffiInfo = JS.FFIInfo jsPath content aliasStr
              in [(jsPath, ffiInfo)]
            Nothing -> []
        _ -> []
