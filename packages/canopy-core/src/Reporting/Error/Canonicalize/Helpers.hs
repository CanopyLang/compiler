{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Canonicalize.Helpers - Shared rendering helpers for canonicalization errors
--
-- This module provides the low-level rendering helpers used by
-- 'Reporting.Error.Canonicalize' to build 'Report.Report' values.
-- All functions take primitive arguments (regions, names, source) rather
-- than the full 'Error' sum type, so this module has no dependency on the
-- parent error module and cannot participate in circular imports.
module Reporting.Error.Canonicalize.Helpers
  ( -- * Report builders
    nameClash,
    ambiguousName,
    notFound,
    unboundTypeVars,
    aliasRecursionReport,
    -- * Doc helpers
    aliasToUnionDoc,
    toKindInfo,
    toQualString,
    -- * Utility
    extractReportMessage,
  )
where

import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Canopy.ModuleName as ModuleName
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Reporting.Doc (Doc, (<+>))
import qualified Reporting.Doc as Doc
import qualified Reporting.Annotation as Ann
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type as RT
import qualified Reporting.Report as Report
import qualified Reporting.Suggest as Suggest

-- | Extract the body 'Doc' from a 'Report.Report'.
--
-- Used so that diagnostic helpers can reuse message-building logic from
-- the legacy 'toReport' functions without duplicating it.
extractReportMessage :: Report.Report -> Doc.Doc
extractReportMessage (Report.Report _ _ _ msg) = msg

-- | Map a VarKind tag to the (article, kind-label, name-doc) triple used in messages.
--
-- Takes the kind as a string tag to avoid importing the Error sum type.
toKindInfo :: String -> Name.Name -> (Doc, Doc, Doc)
toKindInfo kind name =
  case kind of
    "op" ->
      ("an", "operator", "(" <> Doc.fromName name <> ")")
    "pattern" ->
      ("a", "pattern", "`" <> Doc.fromName name <> "`")
    "type" ->
      ("a", "type", "`" <> Doc.fromName name <> "`")
    _ ->
      ("a", "value", "`" <> Doc.fromName name <> "`")

-- | Build a qualified name string from a module prefix and local name.
toQualString :: Name.Name -> Name.Name -> String
toQualString prefix name =
  Name.toChars prefix <> ("." <> Name.toChars name)

-- | Render a name-clash report (used for duplicate declarations, types, etc.).
nameClash :: Code.Source -> Ann.Region -> Ann.Region -> String -> Report.Report
nameClash source r1 r2 messageThatEndsWithPunctuation =
  Report.Report "NAME CLASH" r2 [] $
    Code.toPair
      source
      r1
      r2
      ( Doc.reflow messageThatEndsWithPunctuation,
        "How can I know which one you want? Rename one of them!"
      )
      ( Doc.reflow (messageThatEndsWithPunctuation <> " One here:"),
        "And another one here:",
        "How can I know which one you want? Rename one of them!"
      )

-- | Render an ambiguous-name report (for variables, types, variants, or operators).
ambiguousName ::
  Code.Source ->
  Ann.Region ->
  Maybe Name.Name ->
  Name.Name ->
  ModuleName.Canonical ->
  OneOrMore.OneOrMore ModuleName.Canonical ->
  String ->
  Report.Report
ambiguousName source region maybePrefix name h hs thing =
  let possibleHomes = List.sort (h : OneOrMore.destruct (:) hs)
   in Report.Report "AMBIGUOUS NAME" region [] . Code.toSnippet source region Nothing $
        case maybePrefix of
          Nothing -> buildNoPrefixBody name possibleHomes
          Just prefix -> buildPrefixBody prefix name possibleHomes thing

-- | Build the ambiguous-name message body when there is no qualifier prefix.
buildNoPrefixBody :: Name.Name -> [ModuleName.Canonical] -> (Doc, Doc)
buildNoPrefixBody name possibleHomes =
  let homeToYellowDoc (ModuleName.Canonical _ home) =
        Doc.dullyellow (Doc.fromName home <> "." <> Doc.fromName name)
   in ( Doc.reflow ("This usage of `" <> (Name.toChars name <> "` is ambiguous:")),
        Doc.stack
          [ Doc.reflow
              ( "This name is exposed by "
                  <> show (length possibleHomes)
                  <> " of your imports, so I am not sure which one to use:"
              ),
            Doc.indent 4 . Doc.vcat $ fmap homeToYellowDoc possibleHomes,
            Doc.reflow
              "I recommend using qualified names for imported values. I also recommend having\
              \ at most one `exposing (..)` per file to make name clashes like this less common\
              \ in the long run.",
            Doc.link "Note" "Check out" "imports" "for more info on the import syntax."
          ]
      )

-- | Build the ambiguous-name message body when a qualifier prefix is present.
buildPrefixBody :: Name.Name -> Name.Name -> [ModuleName.Canonical] -> String -> (Doc, Doc)
buildPrefixBody prefix name possibleHomes thing =
  let homeToYellowDoc (ModuleName.Canonical _ home) =
        if prefix == home
          then Doc.cyan "import" <+> Doc.fromName home
          else Doc.cyan "import" <+> Doc.fromName home <+> Doc.cyan "as" <+> Doc.fromName prefix
      eitherOrAny =
        if length possibleHomes == 2 then "either" else "any"
   in ( Doc.reflow ("This usage of `" <> (toQualString prefix name <> "` is ambiguous.")),
        Doc.stack
          [ Doc.reflow ("It could refer to a " <> (thing <> (" from " <> (eitherOrAny <> " of these imports:")))),
            Doc.indent 4 . Doc.vcat $ fmap homeToYellowDoc possibleHomes,
            Doc.reflowLink "Read" "imports" "to learn how to clarify which one you want."
          ]
      )

-- | Render a not-found report for a variable, type, variant, or operator.
--
-- The 'PossibleNames' information is passed as its constituent fields to
-- avoid any dependency on the parent module's type definitions.
notFound ::
  Code.Source ->
  Ann.Region ->
  Maybe Name.Name ->
  Name.Name ->
  String ->
  Set.Set Name.Name ->
  Map.Map Name.Name (Set.Set Name.Name) ->
  Report.Report
notFound source region maybePrefix name thing locals quals =
  let givenName = maybe Name.toChars toQualString maybePrefix name
      possibleNames = buildPossibleNames locals quals
      nearbyNames = take 4 (Suggest.sort givenName id possibleNames)
   in Report.Report "NAMING ERROR" region nearbyNames $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow ("I cannot find a `" <> (givenName <> ("` " <> (thing <> ":")))),
            buildNotFoundDetails maybePrefix name quals nearbyNames
          )

-- | Flatten qualified and unqualified possible names into a single list.
buildPossibleNames :: Set.Set Name.Name -> Map.Map Name.Name (Set.Set Name.Name) -> [String]
buildPossibleNames locals quals =
  let addQuals prefix localSet acc =
        Set.foldr (\x xs -> toQualString prefix x : xs) acc localSet
   in Map.foldrWithKey addQuals (fmap Name.toChars (Set.toList locals)) quals

-- | Build the "details" section of a not-found report.
buildNotFoundDetails :: Maybe Name.Name -> Name.Name -> Map.Map Name.Name (Set.Set Name.Name) -> [String] -> Doc
buildNotFoundDetails maybePrefix name quals nearbyNames =
  let toDetails noSuggest yesSuggest =
        case nearbyNames of
          [] ->
            Doc.stack
              [ Doc.reflow noSuggest,
                Doc.link "Hint" "Read" "imports" "to see how `import` declarations work in Canopy."
              ]
          suggestions ->
            Doc.stack
              [ Doc.reflow yesSuggest,
                (Doc.indent 4 . Doc.vcat) (fmap (Doc.dullyellow . Doc.fromChars) suggestions),
                Doc.link "Hint" "Read" "imports" "to see how `import` declarations work in Canopy."
              ]
   in case maybePrefix of
        Nothing ->
          toDetails
            "Is there an `import` or `exposing` missing up top?"
            "These names seem close though:"
        Just prefix ->
          case Map.lookup prefix quals of
            Nothing ->
              toDetails
                ("I cannot find a `" <> (Name.toChars prefix <> "` module. Is there an `import` for it?"))
                ("I cannot find a `" <> (Name.toChars prefix <> "` import. These names seem close though:"))
            Just _ ->
              toDetails
                ("The `" <> (Name.toChars prefix <> ("` module does not expose a `" <> (Name.toChars name <> ("` " <> ".")))))
                ("The `" <> (Name.toChars prefix <> ("` module does not expose a `" <> (Name.toChars name <> ("` " <> ". These names seem close though:")))))

-- | Render an unbound-type-variable report.
unboundTypeVars ::
  Code.Source ->
  Ann.Region ->
  [Doc.Doc] ->
  Name.Name ->
  [Name.Name] ->
  (Name.Name, Ann.Region) ->
  [(Name.Name, Ann.Region)] ->
  Report.Report
unboundTypeVars source declRegion tipe typeName allVars (unboundVar, varRegion) moreUnbound =
  let (title, subRegion, overview) = buildUnboundOverview typeName tipe unboundVar varRegion moreUnbound
   in Report.Report title declRegion [] $
        Code.toSnippet
          source
          declRegion
          subRegion
          ( Doc.fillSep overview,
            buildUnboundSuggestion tipe typeName allVars unboundVar moreUnbound
          )

-- | Compute the title, sub-region, and overview for an unbound-type-variable report.
buildUnboundOverview ::
  Name.Name ->
  [Doc.Doc] ->
  Name.Name ->
  Ann.Region ->
  [(Name.Name, Ann.Region)] ->
  (String, Maybe Ann.Region, [Doc.Doc])
buildUnboundOverview typeName tipe unboundVar varRegion moreUnbound =
  let backQuote n = "`" <> Doc.fromName n <> "`"
   in case fmap fst moreUnbound of
        [] ->
          ( "UNBOUND TYPE VARIABLE",
            Just varRegion,
            ["The", backQuote typeName] <> (tipe <> ["uses", "an", "unbound", "type", "variable", Doc.dullyellow (backQuote unboundVar), "in", "its", "definition:"])
          )
        vars ->
          ( "UNBOUND TYPE VARIABLES",
            Nothing,
            ["Type", "variables"] <> (Doc.commaSep "and" Doc.dullyellow (Doc.fromName unboundVar : fmap Doc.fromName vars) <> (["are", "unbound", "in", "the", backQuote typeName] <> (tipe <> ["definition:"])))
          )

-- | Build the suggestion Doc for an unbound-type-variable report.
buildUnboundSuggestion ::
  [Doc.Doc] ->
  Name.Name ->
  [Name.Name] ->
  Name.Name ->
  [(Name.Name, Ann.Region)] ->
  Doc.Doc
buildUnboundSuggestion tipe typeName allVars unboundVar moreUnbound =
  Doc.stack
    [ Doc.reflow "You probably need to change the declaration to something like this:",
      Doc.indent 4 . Doc.hsep $
        tipe
          <> [Doc.fromName typeName]
          <> fmap Doc.fromName allVars
          <> fmap (Doc.green . Doc.fromName) (unboundVar : fmap fst moreUnbound)
          <> ["=", "..."],
      Doc.reflow
        ( "Why? Well, imagine one `"
            <> Name.toChars typeName
            <> "` where `"
            <> Name.toChars unboundVar
            <> "` is an Int and another where it is a Bool. When we explicitly list the type\
               \ variables, the type checker can see that they are actually different types."
        )
    ]

-- | Render a recursive-alias report.
aliasRecursionReport :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Src.Type -> [Name.Name] -> Report.Report
aliasRecursionReport source region name args tipe others =
  case others of
    [] ->
      Report.Report "ALIAS PROBLEM" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( "This type alias is recursive, forming an infinite type!",
            Doc.stack
              [ Doc.reflow
                  "When I expand a recursive type alias, it just keeps getting bigger and bigger.\
                  \ So dealiasing results in an infinitely large type! Try this instead:",
                Doc.indent 4 (aliasToUnionDoc name args tipe),
                Doc.link
                  "Hint"
                  "This is kind of a subtle distinction. I suggested the naive fix, but I recommend reading"
                  "recursive-alias"
                  "for ideas on how to do better."
              ]
          )
    _ ->
      Report.Report "ALIAS PROBLEM" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( "This type alias is part of a mutually recursive set of type aliases.",
            Doc.stack
              [ "It is part of this cycle of type aliases:",
                Doc.cycle 4 name others,
                Doc.reflow "You need to convert at least one of these type aliases into a `type`.",
                Doc.link
                  "Note"
                  "Read"
                  "recursive-alias"
                  "to learn why this `type` vs `type alias` distinction matters. It is subtle but important!"
              ]
          )

-- | Render the alias-to-union conversion suggestion Doc.
aliasToUnionDoc :: Name.Name -> [Name.Name] -> Src.Type -> Doc
aliasToUnionDoc name args tipe =
  Doc.vcat
    [ Doc.dullyellow $
        "type" <+> Doc.fromName name <+> (foldr (((<+>)) . Doc.fromName) "=" args),
      Doc.green $
        Doc.indent 4 (Doc.fromName name),
      Doc.dullyellow $
        Doc.indent 8 (RT.srcToDoc RT.App tipe)
    ]
