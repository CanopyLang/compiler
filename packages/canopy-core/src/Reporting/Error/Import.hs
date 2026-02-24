{-# LANGUAGE OverloadedStrings #-}

module Reporting.Error.Import
  ( Error (..),
    Problem (..),
    toDiagnostic,
  )
where

import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Reporting.Annotation as A
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..), Suggestion (..), Confidence (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as D
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code
import qualified Reporting.Suggest as Suggest

-- ERROR

data Error = Error
  { _region :: A.Region,
    _import :: ModuleName.Raw,
    _unimported :: Set.Set ModuleName.Raw,
    _problem :: Problem
  }
  deriving (Show)

data Problem
  = NotFound
  | Ambiguous FilePath [FilePath] Pkg.Name [Pkg.Name]
  | AmbiguousLocal FilePath FilePath [FilePath]
  | AmbiguousForeign Pkg.Name Pkg.Name [Pkg.Name]
  deriving (Show)

-- TO DIAGNOSTIC

-- | Convert an import error to a structured 'Diagnostic'.
--
-- Each import error problem maps to a specific error code:
--
-- @
-- NotFound       -> E0200
-- Ambiguous      -> E0201
-- AmbiguousLocal -> E0202
-- AmbiguousForeign -> E0203
-- @
toDiagnostic :: Code.Source -> Error -> Diagnostic
toDiagnostic source (Error region name unimportedModules problem) =
  case problem of
    NotFound ->
      notFoundDiagnostic source region name unimportedModules
    Ambiguous path _ pkg _ ->
      ambiguousDiagnostic region name path pkg
    AmbiguousLocal path1 path2 paths ->
      ambiguousLocalDiagnostic region name path1 path2 paths
    AmbiguousForeign pkg1 pkg2 pkgs ->
      ambiguousForeignDiagnostic region name pkg1 pkg2 pkgs

notFoundDiagnostic :: Code.Source -> A.Region -> ModuleName.Raw -> Set.Set ModuleName.Raw -> Diagnostic
notFoundDiagnostic source region name unimportedModules =
  Diag.makeDiagnostic
    (EC.importError 0)
    Diag.SError
    Diag.PhaseImport
    "MODULE NOT FOUND"
    (Text.pack ("Cannot find module `" <> ModuleName.toChars name <> "`"))
    (LabeledSpan region (Text.pack ("module `" <> ModuleName.toChars name <> "` not found")) SpanPrimary)
    ( Code.toSnippet
        source
        region
        Nothing
        ( D.reflow ("You are trying to import a `" <> (ModuleName.toChars name <> "` module:")),
          D.stack
            [ D.reflow
                "I checked the \"dependencies\" and \"source-directories\" listed in your canopy.json,\
                \ but I cannot find it! Maybe it is a typo for one of these names?",
              (D.dullyellow . D.indent 4) . D.vcat $ fmap D.fromName suggestions,
              installHint name
            ]
        )
    )
    & addSuggestions name suggestions
  where
    suggestions = toSuggestions name unimportedModules

    addSuggestions :: ModuleName.Raw -> [ModuleName.Raw] -> Diagnostic -> Diagnostic
    addSuggestions _ [] diag = diag
    addSuggestions _modName (best : _) diag =
      Diag.addSuggestion
        (Suggestion region (Text.pack (ModuleName.toChars best)) (Text.pack ("Did you mean `" <> ModuleName.toChars best <> "`?")) Likely)
        diag

    installHint :: ModuleName.Raw -> D.Doc
    installHint modName =
      case Map.lookup modName Pkg.suggestions of
        Nothing ->
          D.toSimpleHint
            "If it is not a typo, check the \"dependencies\" and \"source-directories\"\
            \ of your canopy.json to make sure all the packages you need are listed there!"
        Just dependency ->
          D.toFancyHint
            [ "Maybe",
              "you",
              "want",
              "the",
              "`" <> D.fromName modName <> "`",
              "module",
              "defined",
              "in",
              "the",
              D.fromChars (Pkg.toChars dependency),
              "package?",
              "Running",
              D.green (D.fromChars ("canopy install " <> Pkg.toChars dependency)),
              "should",
              "make",
              "it",
              "available!"
            ]

    (&) = flip ($)

ambiguousDiagnostic :: A.Region -> ModuleName.Raw -> FilePath -> Pkg.Name -> Diagnostic
ambiguousDiagnostic region name path pkg =
  Diag.makeDiagnostic
    (EC.importError 1)
    Diag.SError
    Diag.PhaseImport
    "AMBIGUOUS IMPORT"
    (Text.pack ("Module `" <> ModuleName.toChars name <> "` found in multiple locations"))
    (LabeledSpan region (Text.pack ("ambiguous module `" <> ModuleName.toChars name <> "`")) SpanPrimary)
    ( D.stack
        [ D.reflow ("You are trying to import a `" <> (ModuleName.toChars name <> "` module:")),
          D.fillSep
            [ "But",
              "I",
              "found",
              "multiple",
              "modules",
              "with",
              "that",
              "name.",
              "One",
              "in",
              "the",
              D.dullyellow (D.fromChars (Pkg.toChars pkg)),
              "package,",
              "and",
              "another",
              "defined",
              "locally",
              "in",
              "the",
              D.dullyellow (D.fromChars path),
              "file."
            ],
          D.reflow "Try changing the name of the locally defined module to clear up the ambiguity?"
        ]
    )

ambiguousLocalDiagnostic :: A.Region -> ModuleName.Raw -> FilePath -> FilePath -> [FilePath] -> Diagnostic
ambiguousLocalDiagnostic region name path1 path2 paths =
  Diag.makeDiagnostic
    (EC.importError 2)
    Diag.SError
    Diag.PhaseImport
    "AMBIGUOUS IMPORT"
    (Text.pack ("Module `" <> ModuleName.toChars name <> "` found in multiple source directories"))
    (LabeledSpan region (Text.pack ("ambiguous module `" <> ModuleName.toChars name <> "`")) SpanPrimary)
    ( D.stack
        [ D.reflow ("You are trying to import a `" <> (ModuleName.toChars name <> "` module:")),
          D.reflow "But I found multiple files in your \"source-directories\" with that name:",
          (D.dullyellow . D.indent 4) . D.vcat $ fmap D.fromChars (path1 : path2 : paths),
          D.reflow "Change the module names to be distinct!"
        ]
    )

ambiguousForeignDiagnostic :: A.Region -> ModuleName.Raw -> Pkg.Name -> Pkg.Name -> [Pkg.Name] -> Diagnostic
ambiguousForeignDiagnostic region name pkg1 pkg2 pkgs =
  Diag.makeDiagnostic
    (EC.importError 3)
    Diag.SError
    Diag.PhaseImport
    "AMBIGUOUS IMPORT"
    (Text.pack ("Module `" <> ModuleName.toChars name <> "` found in multiple packages"))
    (LabeledSpan region (Text.pack ("ambiguous module `" <> ModuleName.toChars name <> "`")) SpanPrimary)
    ( D.stack
        [ D.reflow ("You are trying to import a `" <> (ModuleName.toChars name <> "` module:")),
          D.reflow "But multiple packages in your \"dependencies\" expose a module with that name:",
          (D.dullyellow . D.indent 4) . D.vcat $ fmap (D.fromChars . Pkg.toChars) (pkg1 : pkg2 : pkgs),
          D.reflow "The current recommendation is to pick just one of them."
        ]
    )

-- HELPERS

toSuggestions :: ModuleName.Raw -> Set.Set ModuleName.Raw -> [ModuleName.Raw]
toSuggestions name unimportedModules =
  take 4 $
    Suggest.sort (ModuleName.toChars name) ModuleName.toChars (Set.toList unimportedModules)
