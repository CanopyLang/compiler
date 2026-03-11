
-- | Query-based type checking with caching and debug logging.
--
-- This module wraps the existing Type.Constrain and Type.Solve
-- implementations in a query-based architecture with comprehensive
-- debug logging. Errors are reported as structured 'Diagnostic' values.
--
-- @since 0.19.1
module Queries.Type.Check
  ( -- * Query Execution
    typeCheckModuleQuery,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString as BS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Canopy.Data.NonEmptyList (List)
import qualified Canopy.Data.NonEmptyList as NE
import qualified Data.Text as Text
import Logging.Event (LogEvent (..), TypeStats (..))
import qualified Logging.Logger as Log
import Query.Simple
import qualified Reporting.Error.Type as Error
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Type.Constrain.Module as Constrain
import qualified Type.Solve as Solve

-- | Count errors in list.
countErrors :: List a -> Int
countErrors (NE.List _ xs) = 1 + length xs

-- | Execute a type check module query.
--
-- Extracts opaque alias bounds from dependency interfaces and passes them
-- to the solver so that opaque bounded types satisfy super type constraints.
typeCheckModuleQuery ::
  Map ModuleName.Raw Interface.Interface ->
  FilePath ->
  Can.Module ->
  IO (Either QueryError (Map Name.Name Can.Annotation))
typeCheckModuleQuery ifaces path canonical = do
  let modName = Can._name canonical
      modNameText = Text.pack (show modName)
      ifaceBounds = Solve.extractAllInterfaceBounds ifaces
      localAliasBounds = Solve.extractBoundsFromAliases modName (Can._aliases canonical)
      localUnionBounds = Solve.extractBoundsFromUnions modName (Can._unions canonical)
      bounds = Map.union (Map.union ifaceBounds localAliasBounds) localUnionBounds

  Log.logEvent (TypeConstrainStarted modNameText)

  constraint <- Constrain.constrain canonical

  Log.logEvent (TypeSolveStarted modNameText 0)
  solveResult <- Solve.runWithBounds bounds constraint

  case solveResult of
    Left errors -> do
      Log.logEvent (TypeSolveFailed modNameText (countErrors errors))
      Left <$> processErrors path errors
    Right typeMap -> do
      let bindings = Map.size typeMap
      Log.logEvent (TypeSolveCompleted modNameText (TypeStats bindings 0 0))
      validateAbilities canonical typeMap

-- | Validate ability constraints after successful type solving.
--
-- Checks that all impl declarations in the module are complete: every
-- method declared by the ability has a corresponding implementation.
-- Returns the type map on success, or a 'QueryError' on failure.
validateAbilities ::
  Can.Module ->
  Map Name.Name Can.Annotation ->
  IO (Either QueryError (Map Name.Name Can.Annotation))
validateAbilities canonical typeMap =
  case validateImplCompleteness (Can._abilities canonical) (Can._impls canonical) of
    [] -> return (Right typeMap)
    errs -> return (Left (AbilityValidationError errs))

-- | Check that every impl provides all methods declared by its ability.
validateImplCompleteness ::
  Map Name.Name Can.Ability ->
  [Can.Impl] ->
  [Text.Text]
validateImplCompleteness abilities = concatMap checkImpl
  where
    checkImpl impl =
      case Map.lookup (Can._implAbility impl) abilities of
        Nothing -> []
        Just ability ->
          let required = Map.keys (Can._abilityMethods ability)
              provided = Map.keys (Can._implMethods impl)
              missing = filter (\m -> notElem m provided) required
          in case missing of
            [] -> []
            ms ->
              [ Text.concat
                  [ "Incomplete implementation of '"
                  , nameText (Can._implAbility impl)
                  , "': missing "
                  , Text.intercalate ", " (fmap nameText ms)
                  ]
              ]

-- | Convert a Name to Text.
nameText :: Name.Name -> Text.Text
nameText = Text.pack . Name.toChars

-- | Convert type errors to 'DiagnosticError' with structured diagnostics.
processErrors :: FilePath -> List Error.Error -> IO QueryError
processErrors path errors = do
  sourceBytes <- BS.readFile path
  let source = Code.toSource sourceBytes
      localizer = Localizer.empty
      diagnostics = fmap (Error.toDiagnostic localizer source) (NE.toList errors)
  pure (DiagnosticError path diagnostics)
