{-# LANGUAGE OverloadedStrings #-}

module Reporting.Error
  ( Module (..),
    Error (..),
    toDiagnostics,
    toDiagnosticDoc,
    toDiagnosticJson,
    filterCascades,
    filterCascadeList,
  )
where

import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString as B
import qualified Data.NonEmptyList as NE
import qualified Data.OneOrMore as OneOrMore
import qualified File
import Json.Encode ((==>))
import qualified Json.Encode as E
import qualified Reporting.Annotation as A
import qualified Reporting.Doc as D
import qualified Reporting.Error.Canonicalize as Canonicalize
import qualified Reporting.Error.Docs as Docs
import qualified Reporting.Error.Import as Import
import qualified Reporting.Error.Main as Main
import qualified Reporting.Error.Pattern as Pattern
import qualified Reporting.Error.Syntax as Syntax
import qualified Reporting.Error.Type as Type
import Reporting.Diagnostic (Diagnostic)
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type.Localizer as L
import qualified System.FilePath as FP

-- MODULE

data Module = Module
  { _name :: ModuleName.Raw,
    _absolutePath :: FilePath,
    _modificationTime :: File.Time,
    _source :: B.ByteString,
    _error :: Error
  }

-- ERRORS

data Error
  = BadSyntax Syntax.Error
  | BadImports (NE.List Import.Error)
  | BadNames (OneOrMore.OneOrMore Canonicalize.Error)
  | BadTypes L.Localizer (NE.List Type.Error)
  | BadMains L.Localizer (OneOrMore.OneOrMore Main.Error)
  | BadPatterns (NE.List Pattern.Error)
  | BadDocs Docs.Error
  deriving (Show)

-- TO DIAGNOSTICS

-- | Convert an 'Error' to structured 'Diagnostic' values.
--
-- Dispatches to the per-phase @toDiagnostic@ functions.
toDiagnostics :: Code.Source -> Error -> NE.List Diagnostic
toDiagnostics source err =
  case err of
    BadSyntax syntaxError ->
      NE.List (Syntax.toDiagnostic source syntaxError) []
    BadImports errs ->
      fmap (Import.toDiagnostic source) errs
    BadNames errs ->
      fmap (Canonicalize.toDiagnostic source) (OneOrMore.destruct NE.List errs)
    BadTypes localizer errs ->
      fmap (Type.toDiagnostic localizer source) errs
    BadMains localizer errs ->
      fmap (Main.toDiagnostic localizer source) (OneOrMore.destruct NE.List errs)
    BadPatterns errs ->
      fmap (Pattern.toDiagnostic source) errs
    BadDocs docsErr ->
      Docs.toDiagnostics source docsErr

-- | Render a module's diagnostics as a 'D.Doc'.
toDiagnosticDoc :: FilePath -> Module -> D.Doc
toDiagnosticDoc root (Module _ absolutePath _ source err) =
  D.vcat (fmap (renderDiag relativePath) (NE.toList filtered))
  where
    diagnostics = toDiagnostics (Code.toSource source) err
    filtered = filterCascades diagnostics
    relativePath = FP.makeRelative root absolutePath

renderDiag :: FilePath -> Diagnostic -> D.Doc
renderDiag relativePath diag =
  D.vcat
    [ Diag.diagnosticToDoc relativePath diag,
      ""
    ]

-- | Encode a module's diagnostics as JSON.
toDiagnosticJson :: Module -> E.Value
toDiagnosticJson (Module name path _ source err) =
  E.object
    [ "path" ==> E.chars path,
      "name" ==> E.name name,
      "problems" ==> E.array (fmap Diag.diagnosticToJson (NE.toList filtered))
    ]
  where
    diagnostics = toDiagnostics (Code.toSource source) err
    filtered = filterCascades diagnostics

-- CASCADE PREVENTION

-- | Filter cascading errors from a diagnostic list.
--
-- When a single root cause produces many downstream errors (e.g., a
-- missing import causing dozens of name-not-found and type-mismatch
-- errors), this function limits the output to the most relevant
-- diagnostics. It deduplicates by error code within overlapping
-- regions and limits errors per phase.
filterCascades :: NE.List Diagnostic -> NE.List Diagnostic
filterCascades (NE.List first rest) =
  NE.List first (dedup [first] rest)

-- | Filter cascading diagnostics from a plain list.
--
-- Convenience wrapper around 'filterCascades' for the common case
-- where diagnostics are stored in a regular list rather than 'NE.List'.
filterCascadeList :: [Diagnostic] -> [Diagnostic]
filterCascadeList [] = []
filterCascadeList (d : ds) = NE.toList (filterCascades (NE.List d ds))

-- | Remove diagnostics with duplicate error codes at overlapping regions.
dedup :: [Diagnostic] -> [Diagnostic] -> [Diagnostic]
dedup _seen [] = []
dedup seen (d : ds)
  | isDuplicate seen d = dedup seen ds
  | otherwise = d : dedup (d : seen) ds

-- | Check if a diagnostic duplicates one already seen.
isDuplicate :: [Diagnostic] -> Diagnostic -> Bool
isDuplicate seen diag =
  any (sameCodeAndRegion diag) seen

-- | Two diagnostics are considered duplicates if they share an error
-- code and their primary spans overlap.
sameCodeAndRegion :: Diagnostic -> Diagnostic -> Bool
sameCodeAndRegion d1 d2 =
  Diag._diagCode d1 == Diag._diagCode d2
    && regionsOverlap (Diag._spanRegion (Diag._diagPrimary d1)) (Diag._spanRegion (Diag._diagPrimary d2))

-- | Check if two regions overlap.
regionsOverlap :: A.Region -> A.Region -> Bool
regionsOverlap (A.Region s1 e1) (A.Region s2 e2) =
  posLe s1 e2 && posLe s2 e1

-- | Position less-than-or-equal comparison.
posLe :: A.Position -> A.Position -> Bool
posLe (A.Position r1 c1) (A.Position r2 c2) =
  r1 < r2 || (r1 == r2 && c1 <= c2)

