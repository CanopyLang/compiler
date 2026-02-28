
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
typeCheckModuleQuery ::
  FilePath ->
  Can.Module ->
  IO (Either QueryError (Map Name.Name Can.Annotation))
typeCheckModuleQuery path canonical = do
  let modName = Can._name canonical
      modNameText = Text.pack (show modName)

  Log.logEvent (TypeConstrainStarted modNameText)

  constraint <- Constrain.constrain canonical

  Log.logEvent (TypeSolveStarted modNameText 0)
  solveResult <- Solve.run constraint

  case solveResult of
    Left errors -> do
      Log.logEvent (TypeSolveFailed modNameText (countErrors errors))
      Left <$> processErrors path errors
    Right typeMap -> do
      let bindings = Map.size typeMap
      Log.logEvent (TypeSolveCompleted modNameText (TypeStats bindings 0 0))
      return (Right typeMap)

-- | Convert type errors to 'DiagnosticError' with structured diagnostics.
processErrors :: FilePath -> List Error.Error -> IO QueryError
processErrors path errors = do
  sourceBytes <- BS.readFile path
  let source = Code.toSource sourceBytes
      localizer = Localizer.empty
      diagnostics = fmap (Error.toDiagnostic localizer source) (NE.toList errors)
  pure (DiagnosticError path diagnostics)
