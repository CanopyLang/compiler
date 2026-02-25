{-# OPTIONS_GHC -Wall #-}

-- | Query-based canonicalization with caching and debug logging.
--
-- This module wraps the existing Canonicalize.Module implementation
-- in a query-based architecture with content-hash caching and
-- comprehensive debug logging.
--
-- @since 0.19.1
module Queries.Canonicalize.Module
  ( -- * Query Execution
    canonicalizeModuleQuery,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Module as Canonicalize
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Monad (when)
import qualified Parse.Module as Parse
import qualified Data.ByteString as BS
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.OneOrMore as OneOrMore
import qualified Data.Text as Text
import Logging.Event (LogEvent (..), CanonStats (..), VarResolution (..))
import qualified Logging.Logger as Log
import Query.Simple
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.InternalError as InternalError
import qualified Reporting.Render.Code as Code
import qualified Reporting.Result as Result

-- | Execute a canonicalize module query.
--
-- Accepts the file path for source reading in the error path,
-- producing structured 'DiagnosticError' values on failure.
canonicalizeModuleQuery ::
  FilePath ->
  Pkg.Name ->
  Parse.ProjectType ->
  Map ModuleName.Raw I.Interface ->
  Map String String ->
  Src.Module ->
  IO (Either QueryError Can.Module)
canonicalizeModuleQuery path pkg projectType ifaces ffiContent modul = do
  let modName = Src.getName modul
      modNameText = Text.pack (show modName)

  Log.logEvent (CanonStarted modNameText)

  let result = Canonicalize.canonicalize pkg projectType ifaces ffiContent modul
  case processResult result of
    Left errors -> do
      Log.logEvent (CanonFailed modNameText (Text.pack (show (length errors))))
      queryErr <- toDiagnosticQueryError path errors
      return (Left queryErr)
    Right canonical -> do
      let bindings = Map.size (Can._binops canonical)
      Log.logEvent (CanonCompleted modNameText (CanonStats bindings 0 0))
      enabled <- Log.isEnabled
      when enabled (emitCanonTraceEvents modNameText canonical)
      return (Right canonical)

-- | Process Result type, extracting errors or the canonical module.
processResult ::
  Result.Result i w Error.Error Can.Module ->
  Either [Error.Error] Can.Module
processResult result =
  let (_, output) = Result.run (toEmptyWarnings result)
   in case output of
        Left errors -> Left (OneOrMore.destruct (:) errors)
        Right canonical -> Right canonical

-- | Convert Result to empty warnings type.
toEmptyWarnings ::
  Result.Result i w e a ->
  Result.Result () [w] e a
toEmptyWarnings (Result.Result k) =
  Result.Result
    ( \() w bad good ->
        k phantomInfo phantomWarnings (\_ _ -> bad () w) (\_ _ -> good () w)
    )
  where
    phantomInfo = InternalError.report
      "Queries.Canonicalize.Module.toEmptyWarnings"
      "phantom info value evaluated"
      "The initial info accumulator in toEmptyWarnings should never be evaluated. The CPS callbacks discard it. If this fires, it indicates a change in Result internals."
    phantomWarnings = InternalError.report
      "Queries.Canonicalize.Module.toEmptyWarnings"
      "phantom warnings value evaluated"
      "The initial warnings accumulator in toEmptyWarnings should never be evaluated. The CPS callbacks discard it. If this fires, it indicates a change in Result internals."

-- | Convert canonicalization errors to 'DiagnosticError'.
--
-- Reads source bytes from the file path to enable proper snippet
-- rendering in the structured diagnostic output.
toDiagnosticQueryError :: FilePath -> [Error.Error] -> IO QueryError
toDiagnosticQueryError path errors = do
  sourceBytes <- BS.readFile path
  let source = Code.toSource sourceBytes
      diagnostics = fmap (Error.toDiagnostic source) errors
  pure (DiagnosticError path diagnostics)

-- | Emit TRACE-level resolution events from a canonicalized module.
--
-- Walks the canonical module to extract aggregate resolution statistics
-- and emits CanonVarResolved events. This avoids modifying the pure
-- Result monad used during canonicalization.
emitCanonTraceEvents :: Text.Text -> Can.Module -> IO ()
emitCanonTraceEvents modNameText canonical = do
  let unionCount = Map.size (Can._unions canonical)
  let aliasCount = Map.size (Can._aliases canonical)
  Log.logEvent (CanonVarResolved modNameText (Text.pack ("unions:" <> show unionCount)) ResToplevel)
  Log.logEvent (CanonVarResolved modNameText (Text.pack ("aliases:" <> show aliasCount)) ResToplevel)
