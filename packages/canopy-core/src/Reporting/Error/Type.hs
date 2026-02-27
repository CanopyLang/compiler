{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module Reporting.Error.Type
  ( Error (..),
    -- expectations
    Expected (..),
    Context (..),
    SubContext (..),
    MaybeName (..),
    Category (..),
    PExpected (..),
    PContext (..),
    PCategory (..),
    typeReplace,
    ptypeReplace,
    toDiagnostic,
  )
where

import qualified AST.Canonical as Can
import qualified Data.Index as Index
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.Text as Text
import qualified Reporting.Annotation as Ann
import qualified Reporting.Diagnostic as Diag
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..))
import qualified Reporting.Doc as Doc
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Reporting.Report as Report
import qualified Reporting.Suggest as Suggest
import qualified Type.Error as TypeErr
import Prelude hiding (round)

-- ERRORS

data Error
  = BadExpr Ann.Region Category TypeErr.Type (Expected TypeErr.Type)
  | BadPattern Ann.Region PCategory TypeErr.Type (PExpected TypeErr.Type)
  | InfiniteType Ann.Region Name.Name TypeErr.Type
  deriving (Show)

-- EXPRESSION EXPECTATIONS

data Expected tipe
  = NoExpectation tipe
  | FromContext Ann.Region Context tipe
  | FromAnnotation Name.Name Int SubContext tipe

deriving instance Show a => Show (Expected a)

data Context
  = ListEntry Index.ZeroBased
  | Negate
  | OpLeft Name.Name
  | OpRight Name.Name
  | IfCondition
  | IfBranch Index.ZeroBased
  | CaseBranch Index.ZeroBased
  | CallArity MaybeName Int
  | CallArg MaybeName Index.ZeroBased
  | RecordAccess Ann.Region (Maybe Name.Name) Ann.Region Name.Name
  | RecordUpdateKeys Name.Name (Map.Map Name.Name Can.FieldUpdate)
  | RecordUpdateValue Name.Name
  | Destructure
  deriving (Show)

data SubContext
  = TypedIfBranch Index.ZeroBased
  | TypedCaseBranch Index.ZeroBased
  | TypedBody
  deriving (Show)

data MaybeName
  = FuncName Name.Name
  | CtorName Name.Name
  | OpName Name.Name
  | NoName
  deriving (Show)

data Category
  = List
  | Number
  | Float
  | String
  | Char
  | If
  | Case
  | CallResult MaybeName
  | Lambda
  | Accessor Name.Name
  | Access Name.Name
  | Record
  | Tuple
  | Unit
  | Shader
  | Effects
  | Local Name.Name
  | Foreign Name.Name
  deriving (Show)

-- PATTERN EXPECTATIONS

data PExpected tipe
  = PNoExpectation tipe
  | PFromContext Ann.Region PContext tipe
  deriving (Show)

data PContext
  = PTypedArg Name.Name Index.ZeroBased
  | PCaseMatch Index.ZeroBased
  | PCtorArg Name.Name Index.ZeroBased
  | PListEntry Index.ZeroBased
  | PTail
  deriving (Show)

data PCategory
  = PRecord
  | PUnit
  | PTuple
  | PList
  | PCtor Name.Name
  | PInt
  | PStr
  | PChr
  | PBool
  deriving (Show)

-- HELPERS

typeReplace :: Expected a -> b -> Expected b
typeReplace expectation tipe =
  case expectation of
    NoExpectation _ ->
      NoExpectation tipe
    FromContext region context _ ->
      FromContext region context tipe
    FromAnnotation name arity context _ ->
      FromAnnotation name arity context tipe

ptypeReplace :: PExpected a -> b -> PExpected b
ptypeReplace expectation tipe =
  case expectation of
    PNoExpectation _ ->
      PNoExpectation tipe
    PFromContext region context _ ->
      PFromContext region context tipe

-- TO REPORT

-- TO DIAGNOSTIC

-- | Convert a type error to a structured 'Diagnostic'.
--
-- Wraps the error in the 'Diagnostic' type with structured metadata:
-- error code, severity, phase, summary text, and labeled source spans.
toDiagnostic :: Localizer.Localizer -> Code.Source -> Error -> Diagnostic
toDiagnostic localizer source err =
  case err of
    BadExpr region category tipe expected ->
      badExprDiagnostic localizer source region category tipe expected
    BadPattern region category tipe expected ->
      badPatternDiagnostic localizer source region category tipe expected
    InfiniteType region name tipe ->
      infiniteTypeDiagnostic localizer source region name tipe

-- | Produce a diagnostic for a 'BadExpr' type error.
--
-- Delegates message generation to 'toExprReport' to avoid duplicating the
-- complex dispatch logic, then wraps the result with structured metadata.
badExprDiagnostic :: Localizer.Localizer -> Code.Source -> Ann.Region -> Category -> TypeErr.Type -> Expected TypeErr.Type -> Diagnostic
badExprDiagnostic localizer source region category tipe expected =
  Diag.makeDiagnostic
    (EC.typeError 0)
    Diag.SError
    Diag.PhaseType
    (Text.pack (categoryTitle category))
    (Text.pack (categorySummary category))
    (LabeledSpan region "type mismatch here" SpanPrimary)
    (Report._message (toExprReport source localizer region category tipe expected))

-- | Produce a diagnostic for a 'BadPattern' type error.
--
-- Delegates message generation to 'toPatternReport' to avoid duplicating
-- the complex dispatch logic, then wraps the result with structured metadata.
badPatternDiagnostic :: Localizer.Localizer -> Code.Source -> Ann.Region -> PCategory -> TypeErr.Type -> PExpected TypeErr.Type -> Diagnostic
badPatternDiagnostic localizer source region category tipe expected =
  Diag.makeDiagnostic
    (EC.typeError 1)
    Diag.SError
    Diag.PhaseType
    "TYPE MISMATCH IN PATTERN"
    (Text.pack (patternCategorySummary category))
    (LabeledSpan region "pattern type mismatch here" SpanPrimary)
    (Report._message (toPatternReport source localizer region category tipe expected))

-- | Produce a diagnostic for an 'InfiniteType' error.
--
-- Constructs the message doc directly from the existing 'toInfiniteReport'
-- helper to keep message content consistent.
infiniteTypeDiagnostic :: Localizer.Localizer -> Code.Source -> Ann.Region -> Name.Name -> TypeErr.Type -> Diagnostic
infiniteTypeDiagnostic localizer source region name tipe =
  Diag.makeDiagnostic
    (EC.typeError 2)
    Diag.SError
    Diag.PhaseType
    "INFINITE TYPE"
    (Text.pack ("Infinite type inferred for " <> Name.toChars name))
    (LabeledSpan region "infinite type here" SpanPrimary)
    (Report._message (toInfiniteReport source localizer region name tipe))

-- | Map a 'Category' to a display title for diagnostic output.
--
-- The title is used as the diagnostic header shown to the user. All
-- Category-level mismatches use "TYPE MISMATCH"; arity errors are
-- signalled at the Context level inside 'toExprReport'.
categoryTitle :: Category -> String
categoryTitle _ = "TYPE MISMATCH"

-- | Map a 'Category' to a one-line summary for diagnostic output.
--
-- The summary is shown below the title to orient the user before the
-- detailed message body.
categorySummary :: Category -> String
categorySummary category =
  case category of
    List -> "A list element has the wrong type."
    Number -> "A number has the wrong type."
    Float -> "A float has the wrong type."
    String -> "A string has the wrong type."
    Char -> "A character has the wrong type."
    If -> "An if expression branch has the wrong type."
    Case -> "A case expression branch has the wrong type."
    CallResult _ -> "A function call returns the wrong type."
    Lambda -> "An anonymous function has the wrong type."
    Accessor _ -> "A field accessor has the wrong type."
    Access _ -> "A field access has the wrong type."
    Record -> "A record has the wrong type."
    Tuple -> "A tuple has the wrong type."
    Unit -> "A unit value has the wrong type."
    Shader -> "A shader has the wrong type."
    Effects -> "An effects value has the wrong type."
    Local name -> "The value `" <> Name.toChars name <> "` has the wrong type."
    Foreign name -> "The value `" <> Name.toChars name <> "` has the wrong type."

-- | Map a 'PCategory' to a one-line summary for diagnostic output.
--
-- Used in 'badPatternDiagnostic' to orient the user to which kind of
-- pattern is mismatched.
patternCategorySummary :: PCategory -> String
patternCategorySummary category =
  case category of
    PRecord -> "A record pattern has the wrong type."
    PUnit -> "A unit pattern has the wrong type."
    PTuple -> "A tuple pattern has the wrong type."
    PList -> "A list pattern has the wrong type."
    PCtor name -> "The `" <> Name.toChars name <> "` constructor pattern has the wrong type."
    PInt -> "An integer pattern has the wrong type."
    PStr -> "A string pattern has the wrong type."
    PChr -> "A character pattern has the wrong type."
    PBool -> "A boolean pattern has the wrong type."

-- TO PATTERN REPORT

toPatternReport :: Code.Source -> Localizer.Localizer -> Ann.Region -> PCategory -> TypeErr.Type -> PExpected TypeErr.Type -> Report.Report
toPatternReport source localizer patternRegion category tipe expected =
  Report.Report "TYPE MISMATCH" patternRegion [] $
    case expected of
      PNoExpectation expectedType ->
        Code.toSnippet
          source
          patternRegion
          Nothing
          ( "This pattern is being used in an unexpected way:",
            patternTypeComparison
              localizer
              tipe
              expectedType
              (addPatternCategory "It is" category)
              "But it needs to match:"
              []
          )
      PFromContext region context expectedType ->
        Code.toSnippet source region (Just patternRegion) $
          case context of
            PTypedArg name index ->
              ( Doc.reflow $
                  "The " <> Doc.ordinal index <> " argument to `" <> Name.toChars name <> "` is weird.",
                patternTypeComparison
                  localizer
                  tipe
                  expectedType
                  (addPatternCategory "The argument is a pattern that matches" category)
                  ( "But the type annotation on `" <> Name.toChars name
                      <> "` says the "
                      <> Doc.ordinal index
                      <> " argument should be:"
                  )
                  []
              )
            PCaseMatch index ->
              if index == Index.first
                then
                  ( Doc.reflow "The 1st pattern in this `case` causing a mismatch:",
                    patternTypeComparison
                      localizer
                      tipe
                      expectedType
                      (addPatternCategory "The first pattern is trying to match" category)
                      "But the expression between `case` and `of` is:"
                      [ Doc.reflow "These can never match! Is the pattern the problem? Or is it the expression?"
                      ]
                  )
                else
                  ( Doc.reflow $
                      "The " <> Doc.ordinal index <> " pattern in this `case` does not match the previous ones.",
                    patternTypeComparison
                      localizer
                      tipe
                      expectedType
                      (addPatternCategory ("The " <> Doc.ordinal index <> " pattern is trying to match") category)
                      "But all the previous patterns match:"
                      [ Doc.link
                          "Note"
                          "A `case` expression can only handle one type of value, so you may want to use"
                          "custom-types"
                          "to handle “mixing” types."
                      ]
                  )
            PCtorArg name index ->
              ( Doc.reflow $
                  "The " <> Doc.ordinal index <> " argument to `" <> Name.toChars name <> "` is weird.",
                patternTypeComparison
                  localizer
                  tipe
                  expectedType
                  (addPatternCategory "It is trying to match" category)
                  ( "But `" <> Name.toChars name <> "` needs its "
                      <> Doc.ordinal index
                      <> " argument to be:"
                  )
                  []
              )
            PListEntry index ->
              ( Doc.reflow $
                  "The " <> Doc.ordinal index <> " pattern in this list does not match all the previous ones:",
                patternTypeComparison
                  localizer
                  tipe
                  expectedType
                  (addPatternCategory ("The " <> Doc.ordinal index <> " pattern is trying to match") category)
                  "But all the previous patterns in the list are:"
                  [ Doc.link
                      "Hint"
                      "Everything in a list must be the same type of value. This way, we never\
                      \ run into unexpected values partway through a List.map, List.foldl, etc. Read"
                      "custom-types"
                      "to learn how to “mix” types."
                  ]
              )
            PTail ->
              ( Doc.reflow "The pattern after (::) is causing issues.",
                patternTypeComparison
                  localizer
                  tipe
                  expectedType
                  (addPatternCategory "The pattern after (::) is trying to match" category)
                  "But it needs to match lists like this:"
                  []
              )

-- PATTERN HELPERS

patternTypeComparison :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> String -> String -> [Doc.Doc] -> Doc.Doc
patternTypeComparison localizer actual expected iAmSeeing insteadOf contextHints =
  let (actualDoc, expectedDoc, problems) =
        TypeErr.toComparison localizer actual expected
   in Doc.stack
        ( [ Doc.reflow iAmSeeing,
            Doc.indent 4 actualDoc,
            Doc.reflow insteadOf,
            Doc.indent 4 expectedDoc
          ]
            <> (problemsToHint problems <> contextHints)
        )

addPatternCategory :: String -> PCategory -> String
addPatternCategory iAmTryingToMatch category =
  iAmTryingToMatch
    <> case category of
      PRecord -> " record values of type:"
      PUnit -> " unit values:"
      PTuple -> " tuples of type:"
      PList -> " lists of type:"
      PCtor name -> " `" <> Name.toChars name <> "` values of type:"
      PInt -> " integers:"
      PStr -> " strings:"
      PChr -> " characters:"
      PBool -> " booleans:"

-- EXPR HELPERS

typeComparison :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> String -> String -> [Doc.Doc] -> Doc.Doc
typeComparison localizer actual expected iAmSeeing insteadOf contextHints =
  let (actualDoc, expectedDoc, problems) =
        TypeErr.toComparison localizer actual expected
   in Doc.stack
        ( [ Doc.reflow iAmSeeing,
            Doc.indent 4 actualDoc,
            Doc.reflow insteadOf,
            Doc.indent 4 expectedDoc
          ]
            <> (contextHints <> problemsToHint problems)
        )

loneType :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> Doc.Doc -> [Doc.Doc] -> Doc.Doc
loneType localizer actual expected iAmSeeing furtherDetails =
  let (actualDoc, _, problems) =
        TypeErr.toComparison localizer actual expected
   in Doc.stack
        ( [ iAmSeeing,
            Doc.indent 4 actualDoc
          ]
            <> (furtherDetails <> problemsToHint problems)
        )

addCategory :: String -> Category -> String
addCategory thisIs category =
  case category of
    Local name -> "This `" <> Name.toChars name <> "` value is a:"
    Foreign name -> "This `" <> Name.toChars name <> "` value is a:"
    Access field -> "The value at ." <> Name.toChars field <> " is a:"
    Accessor field -> "This ." <> Name.toChars field <> " field access function has type:"
    If -> "This `if` expression produces:"
    Case -> "This `case` expression produces:"
    List -> thisIs <> " a list of type:"
    Number -> thisIs <> " a number of type:"
    Float -> thisIs <> " a float of type:"
    String -> thisIs <> " a string of type:"
    Char -> thisIs <> " a character of type:"
    Lambda -> thisIs <> " an anonymous function of type:"
    Record -> thisIs <> " a record of type:"
    Tuple -> thisIs <> " a tuple of type:"
    Unit -> thisIs <> " a unit value:"
    Shader -> thisIs <> " a GLSL shader of type:"
    Effects -> thisIs <> " a thing for CORE LIBRARIES ONLY."
    CallResult maybeName ->
      case maybeName of
        NoName -> thisIs <> ":"
        FuncName name -> "This `" <> Name.toChars name <> "` call produces:"
        CtorName name -> "This `" <> Name.toChars name <> "` call produces:"
        OpName _ -> thisIs <> ":"

problemsToHint :: [TypeErr.Problem] -> [Doc.Doc]
problemsToHint problems =
  case problems of
    [] ->
      []
    problem : _ ->
      problemToHint problem

problemToHint :: TypeErr.Problem -> [Doc.Doc]
problemToHint problem =
  case problem of
    TypeErr.IntFloat ->
      [ Doc.fancyLink
          "Note"
          ["Read"]
          "implicit-casts"
          [ "to",
            "learn",
            "why",
            "Canopy",
            "does",
            "not",
            "implicitly",
            "convert",
            "Ints",
            "to",
            "Floats.",
            "Use",
            Doc.green "toFloat",
            "and",
            Doc.green "round",
            "to",
            "do",
            "explicit",
            "conversions."
          ]
      ]
    TypeErr.StringFromInt ->
      [ Doc.toFancyHint
          [ "Want",
            "to",
            "convert",
            "an",
            "Int",
            "into",
            "a",
            "String?",
            "Use",
            "the",
            Doc.green "String.fromInt",
            "function!"
          ]
      ]
    TypeErr.StringFromFloat ->
      [ Doc.toFancyHint
          [ "Want",
            "to",
            "convert",
            "a",
            "Float",
            "into",
            "a",
            "String?",
            "Use",
            "the",
            Doc.green "String.fromFloat",
            "function!"
          ]
      ]
    TypeErr.StringToInt ->
      [ Doc.toFancyHint
          [ "Want",
            "to",
            "convert",
            "a",
            "String",
            "into",
            "an",
            "Int?",
            "Use",
            "the",
            Doc.green "String.toInt",
            "function!"
          ]
      ]
    TypeErr.StringToFloat ->
      [ Doc.toFancyHint
          [ "Want",
            "to",
            "convert",
            "a",
            "String",
            "into",
            "a",
            "Float?",
            "Use",
            "the",
            Doc.green "String.toFloat",
            "function!"
          ]
      ]
    TypeErr.AnythingToBool ->
      [ Doc.toSimpleHint
          "Canopy does not have “truthiness” such that ints and strings and lists\
          \ are automatically converted to booleans. Do that conversion explicitly!"
      ]
    TypeErr.AnythingFromMaybe ->
      [ Doc.toFancyHint
          [ "Use",
            Doc.green "Maybe.withDefault",
            "to",
            "handle",
            "possible",
            "errors.",
            "Longer",
            "term,",
            "it",
            "is",
            "usually",
            "better",
            "to",
            "write",
            "out",
            "the",
            "full",
            "`case`",
            "though!"
          ]
      ]
    TypeErr.ArityMismatch x y ->
      [ Doc.toSimpleHint $
          if x < y
            then "It looks like it takes too few arguments. I was expecting " <> (show (y - x) <> " more.")
            else "It looks like it takes too many arguments. I see " <> (show (x - y) <> " extra.")
      ]
    TypeErr.BadFlexSuper direction super _ tipe ->
      case tipe of
        TypeErr.Lambda {} -> badFlexSuper direction super tipe
        TypeErr.Infinite -> []
        TypeErr.Error -> []
        TypeErr.FlexVar _ -> []
        TypeErr.FlexSuper s _ -> badFlexFlexSuper super s
        TypeErr.RigidVar y -> badRigidVar y (toASuperThing super)
        TypeErr.RigidSuper s _ -> badRigidSuper s (toASuperThing super)
        TypeErr.Type {} -> badFlexSuper direction super tipe
        TypeErr.Record _ _ -> badFlexSuper direction super tipe
        TypeErr.Unit -> badFlexSuper direction super tipe
        TypeErr.Tuple {} -> badFlexSuper direction super tipe
        TypeErr.Alias {} -> badFlexSuper direction super tipe
    TypeErr.BadRigidVar x tipe ->
      case tipe of
        TypeErr.Lambda {} -> badRigidVar x "a function"
        TypeErr.Infinite -> []
        TypeErr.Error -> []
        TypeErr.FlexVar _ -> []
        TypeErr.FlexSuper s _ -> badRigidVar x (toASuperThing s)
        TypeErr.RigidVar y -> badDoubleRigid x y
        TypeErr.RigidSuper _ y -> badDoubleRigid x y
        TypeErr.Type _ n _ -> badRigidVar x ("a `" <> (Name.toChars n <> "` value"))
        TypeErr.Record _ _ -> badRigidVar x "a record"
        TypeErr.Unit -> badRigidVar x "a unit value"
        TypeErr.Tuple {} -> badRigidVar x "a tuple"
        TypeErr.Alias _ n _ _ -> badRigidVar x ("a `" <> (Name.toChars n <> "` value"))
    TypeErr.BadRigidSuper super x tipe ->
      case tipe of
        TypeErr.Lambda {} -> badRigidSuper super "a function"
        TypeErr.Infinite -> []
        TypeErr.Error -> []
        TypeErr.FlexVar _ -> []
        TypeErr.FlexSuper s _ -> badRigidSuper super (toASuperThing s)
        TypeErr.RigidVar y -> badDoubleRigid x y
        TypeErr.RigidSuper _ y -> badDoubleRigid x y
        TypeErr.Type _ n _ -> badRigidSuper super ("a `" <> (Name.toChars n <> "` value"))
        TypeErr.Record _ _ -> badRigidSuper super "a record"
        TypeErr.Unit -> badRigidSuper super "a unit value"
        TypeErr.Tuple {} -> badRigidSuper super "a tuple"
        TypeErr.Alias _ n _ _ -> badRigidSuper super ("a `" <> (Name.toChars n <> "` value"))
    TypeErr.FieldsMissing fields ->
      case fmap (Doc.green . Doc.fromName) fields of
        [] ->
          []
        [f1] ->
          [ Doc.toFancyHint ["Looks", "like", "the", f1, "field", "is", "missing."]
          ]
        fieldDocs ->
          [ Doc.toFancyHint (["Looks", "like", "fields"] <> (Doc.commaSep "and" id fieldDocs <> ["are", "missing."]))
          ]
    TypeErr.FieldTypo typo possibilities ->
      case Suggest.sort (Name.toChars typo) Name.toChars possibilities of
        [] ->
          []
        nearest : _ ->
          [ Doc.toFancyHint
              [ "Seems",
                "like",
                "a",
                "record",
                "field",
                "typo.",
                "Maybe",
                Doc.dullyellow (Doc.fromName typo),
                "should",
                "be",
                Doc.green (Doc.fromName nearest) <> "?"
              ],
            Doc.toSimpleHint
              "Can more type annotations be added? Type annotations always help me give\
              \ more specific messages, and I think they could help a lot in this case!"
          ]

-- BAD RIGID HINTS

badRigidVar :: Name.Name -> String -> [Doc.Doc]
badRigidVar name aThing =
  [ Doc.toSimpleHint
      ( "Your type annotation uses type variable `"
          <> ( Name.toChars name
                 <> ( "` which means ANY type of value can flow through, but your code is saying it specifically wants "
                        <> ( aThing
                               <> ". Maybe change your type annotation to\
                                  \ be more specific? Maybe change the code to be more general?"
                           )
                    )
             )
      ),
    Doc.reflowLink "Read" "type-annotations" "for more advice!"
  ]

badDoubleRigid :: Name.Name -> Name.Name -> [Doc.Doc]
badDoubleRigid x y =
  [ Doc.toSimpleHint
      ( "Your type annotation uses `"
          <> ( Name.toChars x
                 <> ( "` and `"
                        <> ( Name.toChars y
                               <> "` as separate type variables. Your code seems to be saying they are the\
                                  \ same though. Maybe they should be the same in your type annotation?\
                                  \ Maybe your code uses them in a weird way?"
                           )
                    )
             )
      ),
    Doc.reflowLink "Read" "type-annotations" "for more advice!"
  ]

toASuperThing :: TypeErr.Super -> String
toASuperThing super =
  case super of
    TypeErr.Number -> "a `number` value"
    TypeErr.Comparable -> "a `comparable` value"
    TypeErr.CompAppend -> "a `compappend` value"
    TypeErr.Appendable -> "an `appendable` value"

-- BAD SUPER HINTS

badFlexSuper :: TypeErr.Direction -> TypeErr.Super -> TypeErr.Type -> [Doc.Doc]
badFlexSuper direction super tipe =
  case super of
    TypeErr.Comparable ->
      case tipe of
        TypeErr.Record _ _ ->
          [ Doc.link
              "Hint"
              "I do not know how to compare records. I can only compare ints, floats,\
              \ chars, strings, lists of comparable values, and tuples of comparable values.\
              \ Check out"
              "comparing-records"
              "for ideas on how to proceed."
          ]
        TypeErr.Type _ name _ ->
          [ Doc.toSimpleHint
              ( "I do not know how to compare `"
                  <> ( Name.toChars name
                         <> "` values. I can only\
                            \ compare ints, floats, chars, strings, lists of comparable values, and tuples\
                            \ of comparable values."
                     )
              ),
            Doc.reflowLink
              "Check out"
              "comparing-custom-types"
              "for ideas on how to proceed."
          ]
        _ ->
          [ Doc.toSimpleHint
              "I only know how to compare ints, floats, chars, strings, lists of\
              \ comparable values, and tuples of comparable values."
          ]
    TypeErr.Appendable ->
      [ Doc.toSimpleHint "I only know how to append strings and lists."
      ]
    TypeErr.CompAppend ->
      [ Doc.toSimpleHint "Only strings and lists are both comparable and appendable."
      ]
    TypeErr.Number ->
      case tipe of
        TypeErr.Type home name _ | TypeErr.isString home name ->
          case direction of
            TypeErr.Have ->
              [ Doc.toFancyHint ["Try", "using", Doc.green "String.fromInt", "to", "convert", "it", "to", "a", "string?"]
              ]
            TypeErr.Need ->
              [ Doc.toFancyHint ["Try", "using", Doc.green "String.toInt", "to", "convert", "it", "to", "an", "integer?"]
              ]
        _ ->
          [ Doc.toFancyHint ["Only", Doc.green "Int", "and", Doc.green "Float", "values", "work", "as", "numbers."]
          ]

badRigidSuper :: TypeErr.Super -> String -> [Doc.Doc]
badRigidSuper super aThing =
  let (superType, manyThings) =
        case super of
          TypeErr.Number -> ("number", "ints AND floats")
          TypeErr.Comparable -> ("comparable", "ints, floats, chars, strings, lists, and tuples")
          TypeErr.Appendable -> ("appendable", "strings AND lists")
          TypeErr.CompAppend -> ("compappend", "strings AND lists")
   in [ Doc.toSimpleHint
          ( "The `"
              <> ( superType
                     <> ( "` in your type annotation is saying that "
                            <> ( manyThings
                                   <> ( " can flow through, but your code is saying it specifically wants "
                                          <> ( aThing
                                                 <> ". Maybe change your type annotation to\
                                                    \ be more specific? Maybe change the code to be more general?"
                                             )
                                      )
                               )
                        )
                 )
          ),
        Doc.reflowLink "Read" "type-annotations" "for more advice!"
      ]

badFlexFlexSuper :: TypeErr.Super -> TypeErr.Super -> [Doc.Doc]
badFlexFlexSuper s1 s2 =
  let likeThis super =
        case super of
          TypeErr.Number -> "a number"
          TypeErr.Comparable -> "comparable"
          TypeErr.CompAppend -> "a compappend"
          TypeErr.Appendable -> "appendable"
   in [ Doc.toSimpleHint ("There are no values in Canopy that are both " <> (likeThis s1 <> (" and " <> (likeThis s2 <> "."))))
      ]

-- TO EXPR REPORT

toExprReport :: Code.Source -> Localizer.Localizer -> Ann.Region -> Category -> TypeErr.Type -> Expected TypeErr.Type -> Report.Report
toExprReport source localizer exprRegion category tipe expected =
  case expected of
    NoExpectation expectedType ->
      Report.Report "TYPE MISMATCH" exprRegion [] $
        Code.toSnippet
          source
          exprRegion
          Nothing
          ( "This expression is being used in an unexpected way:",
            typeComparison
              localizer
              tipe
              expectedType
              (addCategory "It is" category)
              "But you are trying to use it as:"
              []
          )
    FromAnnotation name _arity subContext expectedType ->
      let thing =
            case subContext of
              TypedIfBranch index -> Doc.ordinal index <> " branch of this `if` expression:"
              TypedCaseBranch index -> Doc.ordinal index <> " branch of this `case` expression:"
              TypedBody -> "body of the `" <> Name.toChars name <> "` definition:"

          itIs =
            case subContext of
              TypedIfBranch index -> "The " <> Doc.ordinal index <> " branch is"
              TypedCaseBranch index -> "The " <> Doc.ordinal index <> " branch is"
              TypedBody -> "The body is"
       in ( Report.Report "TYPE MISMATCH" exprRegion [] . Code.toSnippet source exprRegion Nothing $
              ( Doc.reflow ("Something is off with the " <> thing),
                typeComparison
                  localizer
                  tipe
                  expectedType
                  (addCategory itIs category)
                  ("But the type annotation on `" <> Name.toChars name <> "` says it should be:")
                  []
              )
          )
    FromContext region context expectedType ->
      let mismatch (maybeHighlight, problem, thisIs, insteadOf, furtherDetails) =
            Report.Report "TYPE MISMATCH" exprRegion [] $
              Code.toSnippet
                source
                region
                maybeHighlight
                ( Doc.reflow problem,
                  typeComparison localizer tipe expectedType (addCategory thisIs category) insteadOf furtherDetails
                )

          badType (maybeHighlight, problem, thisIs, furtherDetails) =
            Report.Report "TYPE MISMATCH" exprRegion [] $
              Code.toSnippet
                source
                region
                maybeHighlight
                ( Doc.reflow problem,
                  loneType localizer tipe expectedType (Doc.reflow (addCategory thisIs category)) furtherDetails
                )

          custom maybeHighlight docPair =
            Report.Report "TYPE MISMATCH" exprRegion [] $
              Code.toSnippet source region maybeHighlight docPair
       in case context of
            ListEntry index ->
              let ith = Doc.ordinal index
               in mismatch
                    ( Just exprRegion,
                      "The " <> ith <> " element of this list does not match all the previous elements:",
                      "The " <> ith <> " element is",
                      "But all the previous elements in the list are:",
                      [ Doc.link
                          "Hint"
                          "Everything in a list must be the same type of value. This way, we never\
                          \ run into unexpected values partway through a List.map, List.foldl, etc. Read"
                          "custom-types"
                          "to learn how to “mix” types."
                      ]
                    )
            Negate ->
              badType
                ( Just exprRegion,
                  "I do not know how to negate this type of value:",
                  "It is",
                  [ Doc.fillSep
                      [ "But",
                        "I",
                        "only",
                        "now",
                        "how",
                        "to",
                        "negate",
                        Doc.dullyellow "Int",
                        "and",
                        Doc.dullyellow "Float",
                        "values."
                      ]
                  ]
                )
            OpLeft op ->
              custom (Just exprRegion) $
                opLeftToDocs localizer category op tipe expectedType
            OpRight op ->
              case opRightToDocs localizer category op tipe expectedType of
                EmphBoth details ->
                  custom Nothing details
                EmphRight details ->
                  custom (Just exprRegion) details
            IfCondition ->
              badType
                ( Just exprRegion,
                  "This `if` condition does not evaluate to a boolean value, True or False.",
                  "It is",
                  [ Doc.fillSep ["But", "I", "need", "this", "`if`", "condition", "to", "be", "a", Doc.dullyellow "Bool", "value."]
                  ]
                )
            IfBranch index ->
              let ith = Doc.ordinal index
               in mismatch
                    ( Just exprRegion,
                      "The " <> ith <> " branch of this `if` does not match all the previous branches:",
                      "The " <> ith <> " branch is",
                      "But all the previous branches result in:",
                      [ Doc.link
                          "Hint"
                          "All branches in an `if` must produce the same type of values. This way, no\
                          \ matter which branch we take, the result is always a consistent shape. Read"
                          "custom-types"
                          "to learn how to “mix” types."
                      ]
                    )
            CaseBranch index ->
              let ith = Doc.ordinal index
               in mismatch
                    ( Just exprRegion,
                      "The " <> ith <> " branch of this `case` does not match all the previous branches:",
                      "The " <> ith <> " branch is",
                      "But all the previous branches result in:",
                      [ Doc.link
                          "Hint"
                          "All branches in a `case` must produce the same type of values. This way, no\
                          \ matter which branch we take, the result is always a consistent shape. Read"
                          "custom-types"
                          "to learn how to “mix” types."
                      ]
                    )
            CallArity maybeFuncName numGivenArgs ->
              Report.Report "TOO MANY ARGS" exprRegion [] . Code.toSnippet source region (Just exprRegion) $
                ( case countArgs tipe of
                    0 ->
                      let thisValue =
                            case maybeFuncName of
                              NoName -> "This value"
                              FuncName name -> "The `" <> Name.toChars name <> "` value"
                              CtorName name -> "The `" <> Name.toChars name <> "` value"
                              OpName op -> "The (" <> Name.toChars op <> ") operator"
                       in ( Doc.reflow $ thisValue <> " is not a function, but it was given " <> Doc.args numGivenArgs <> ".",
                            Doc.reflow "Are there any missing commas? Or missing parentheses?"
                          )
                    n ->
                      let thisFunction =
                            case maybeFuncName of
                              NoName -> "This function"
                              FuncName name -> "The `" <> Name.toChars name <> "` function"
                              CtorName name -> "The `" <> Name.toChars name <> "` constructor"
                              OpName op -> "The (" <> Name.toChars op <> ") operator"
                       in ( Doc.reflow $ thisFunction <> " expects " <> Doc.args n <> ", but it got " <> show numGivenArgs <> " instead.",
                            Doc.reflow "Are there any missing commas? Or missing parentheses?"
                          )
                )
            CallArg maybeFuncName index ->
              let ith = Doc.ordinal index

                  thisFunction =
                    case maybeFuncName of
                      NoName -> "this function"
                      FuncName name -> "`" <> Name.toChars name <> "`"
                      CtorName name -> "`" <> Name.toChars name <> "`"
                      OpName op -> "(" <> Name.toChars op <> ")"
               in mismatch
                    ( Just exprRegion,
                      "The " <> ith <> " argument to " <> thisFunction <> " is not what I expect:",
                      "This argument is",
                      "But " <> thisFunction <> " needs the " <> ith <> " argument to be:",
                      if Index.toHuman index == 1
                        then []
                        else
                          [ Doc.toSimpleHint
                              "I always figure out the argument types from left to right. If an argument\
                              \ is acceptable, I assume it is “correct” and move on. So the problem may\
                              \ actually be in one of the previous arguments!"
                          ]
                    )
            RecordAccess recordRegion maybeName fieldRegion field ->
              case TypeErr.iteratedDealias tipe of
                TypeErr.Record fields ext ->
                  custom
                    (Just fieldRegion)
                    ( Doc.reflow $
                        "This "
                          <> maybe "" (\n -> "`" <> Name.toChars n <> "`") maybeName
                          <> " record does not have a `"
                          <> Name.toChars field
                          <> "` field:",
                      case Suggest.sort (Name.toChars field) (Name.toChars . fst) (Map.toList fields) of
                        [] ->
                          Doc.reflow "In fact, it is a record with NO fields!"
                        f : fs ->
                          Doc.stack
                            [ Doc.reflow $
                                "This is usually a typo. Here are the "
                                  <> maybe "" (\n -> "`" <> Name.toChars n <> "`") maybeName
                                  <> " fields that are most similar:",
                              toNearbyRecord localizer f fs ext,
                              Doc.fillSep
                                [ "So",
                                  "maybe",
                                  Doc.dullyellow (Doc.fromName field),
                                  "should",
                                  "be",
                                  Doc.green (Doc.fromName (fst f)) <> "?"
                                ]
                            ]
                    )
                _ ->
                  badType
                    ( Just recordRegion,
                      "This is not a record, so it has no fields to access!",
                      "It is",
                      [ Doc.fillSep
                          [ "But",
                            "I",
                            "need",
                            "a",
                            "record",
                            "with",
                            "a",
                            Doc.dullyellow (Doc.fromName field),
                            "field!"
                          ]
                      ]
                    )
            RecordUpdateKeys record expectedFields ->
              case TypeErr.iteratedDealias tipe of
                TypeErr.Record actualFields ext ->
                  case Map.lookupMin (Map.difference expectedFields actualFields) of
                    Nothing ->
                      mismatch
                        ( Nothing,
                          "Something is off with this record update:",
                          "The `" <> Name.toChars record <> "` record is",
                          "But this update needs it to be compatable with:",
                          [ Doc.reflow
                              "Do you mind creating an <http://sscce.org/> that produces this error message and\
                              \ sharing it at <https://github.com/canopy/error-message-catalog/issues> so we\
                              \ can try to give better advice here?"
                          ]
                        )
                    Just (field, Can.FieldUpdate fieldRegion _) ->
                      let rStr = "`" <> Name.toChars record <> "`"
                          fStr = "`" <> Name.toChars field <> "`"
                       in custom
                            (Just fieldRegion)
                            ( Doc.reflow $
                                "The " <> rStr <> " record does not have a " <> fStr <> " field:",
                              case Suggest.sort (Name.toChars field) (Name.toChars . fst) (Map.toList actualFields) of
                                [] ->
                                  Doc.reflow $ "In fact, " <> rStr <> " is a record with NO fields!"
                                f : fs ->
                                  Doc.stack
                                    [ Doc.reflow $
                                        "This is usually a typo. Here are the " <> rStr <> " fields that are most similar:",
                                      toNearbyRecord localizer f fs ext,
                                      Doc.fillSep
                                        [ "So",
                                          "maybe",
                                          Doc.dullyellow (Doc.fromName field),
                                          "should",
                                          "be",
                                          Doc.green (Doc.fromName (fst f)) <> "?"
                                        ]
                                    ]
                            )
                _ ->
                  badType
                    ( Just exprRegion,
                      "This is not a record, so it has no fields to update!",
                      "It is",
                      [ Doc.reflow "But I need a record!"
                      ]
                    )
            RecordUpdateValue field ->
              mismatch
                ( Just exprRegion,
                  "I cannot update the `" <> Name.toChars field <> "` field like this:",
                  "You are trying to update `" <> Name.toChars field <> "` to be",
                  "But it should be:",
                  [ Doc.toSimpleNote
                      "The record update syntax does not allow you to change the type of fields.\
                      \ You can achieve that with record constructors or the record literal syntax."
                  ]
                )
            Destructure ->
              mismatch
                ( Nothing,
                  "This definition is causing issues:",
                  "You are defining",
                  "But then trying to destructure it as:",
                  []
                )

-- HELPERS

countArgs :: TypeErr.Type -> Int
countArgs tipe =
  case tipe of
    TypeErr.Lambda _ _ stuff ->
      1 + length stuff
    _ ->
      0

-- FIELD NAME HELPERS

toNearbyRecord :: Localizer.Localizer -> (Name.Name, TypeErr.Type) -> [(Name.Name, TypeErr.Type)] -> TypeErr.Extension -> Doc.Doc
toNearbyRecord localizer f fs ext =
  Doc.indent 4 $
    if length fs <= 3
      then RT.vrecord (fmap (fieldToDocs localizer) (f : fs)) (extToDoc ext)
      else RT.vrecordSnippet (fieldToDocs localizer f) (fmap (fieldToDocs localizer) (take 3 fs))

fieldToDocs :: Localizer.Localizer -> (Name.Name, TypeErr.Type) -> (Doc.Doc, Doc.Doc)
fieldToDocs localizer (name, tipe) =
  ( Doc.fromName name,
    TypeErr.toDoc localizer RT.None tipe
  )

extToDoc :: TypeErr.Extension -> Maybe Doc.Doc
extToDoc ext =
  case ext of
    TypeErr.Closed -> Nothing
    TypeErr.FlexOpen x -> Just (Doc.fromName x)
    TypeErr.RigidOpen x -> Just (Doc.fromName x)

-- OP LEFT

opLeftToDocs :: Localizer.Localizer -> Category -> Name.Name -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
opLeftToDocs localizer category op tipe expected =
  case op of
    "+"
      | isString tipe -> badStringAdd
      | isList tipe -> badListAdd localizer category "left" tipe expected
      | otherwise -> badMath localizer category "Addition" "left" "+" tipe expected []
    "*"
      | isList tipe -> badListMul localizer category "left" tipe expected
      | otherwise -> badMath localizer category "Multiplication" "left" "*" tipe expected []
    "-" -> badMath localizer category "Subtraction" "left" "-" tipe expected []
    "^" -> badMath localizer category "Exponentiation" "left" "^" tipe expected []
    "/" -> badFDiv localizer "left" tipe expected
    "//" -> badIDiv localizer "left" tipe expected
    "&&" -> badBool localizer "&&" "left" tipe expected
    "||" -> badBool localizer "||" "left" tipe expected
    "<" -> badCompLeft localizer category "<" "left" tipe expected
    ">" -> badCompLeft localizer category ">" "left" tipe expected
    "<=" -> badCompLeft localizer category "<=" "left" tipe expected
    ">=" -> badCompLeft localizer category ">=" "left" tipe expected
    "++" -> badAppendLeft localizer category tipe expected
    "<|" ->
      ( "The left side of (<|) needs to be a function so I can pipe arguments to it!",
        loneType
          localizer
          tipe
          expected
          (Doc.reflow (addCategory "I am seeing" category))
          [ Doc.reflow "This needs to be some kind of function though!"
          ]
      )
    _ ->
      ( Doc.reflow $
          "The left argument of (" <> Name.toChars op <> ") is causing problems:",
        typeComparison
          localizer
          tipe
          expected
          (addCategory "The left argument is" category)
          ("But (" <> Name.toChars op <> ") needs the left argument to be:")
          []
      )

-- OP RIGHT

data RightDocs
  = EmphBoth (Doc.Doc, Doc.Doc)
  | EmphRight (Doc.Doc, Doc.Doc)

opRightToDocs :: Localizer.Localizer -> Category -> Name.Name -> TypeErr.Type -> TypeErr.Type -> RightDocs
opRightToDocs localizer category op tipe expected =
  case op of
    "+"
      | isFloat expected && isInt tipe -> badCast op FloatInt
      | isInt expected && isFloat tipe -> badCast op IntFloat
      | isString tipe -> EmphRight badStringAdd
      | isList tipe -> EmphRight $ badListAdd localizer category "right" tipe expected
      | otherwise -> EmphRight $ badMath localizer category "Addition" "right" "+" tipe expected []
    "*"
      | isFloat expected && isInt tipe -> badCast op FloatInt
      | isInt expected && isFloat tipe -> badCast op IntFloat
      | isList tipe -> EmphRight $ badListMul localizer category "right" tipe expected
      | otherwise -> EmphRight $ badMath localizer category "Multiplication" "right" "*" tipe expected []
    "-"
      | isFloat expected && isInt tipe -> badCast op FloatInt
      | isInt expected && isFloat tipe -> badCast op IntFloat
      | otherwise ->
        EmphRight $ badMath localizer category "Subtraction" "right" "-" tipe expected []
    "^"
      | isFloat expected && isInt tipe -> badCast op FloatInt
      | isInt expected && isFloat tipe -> badCast op IntFloat
      | otherwise ->
        EmphRight $ badMath localizer category "Exponentiation" "right" "^" tipe expected []
    "/" -> EmphRight $ badFDiv localizer "right" tipe expected
    "//" -> EmphRight $ badIDiv localizer "right" tipe expected
    "&&" -> EmphRight $ badBool localizer "&&" "right" tipe expected
    "||" -> EmphRight $ badBool localizer "||" "right" tipe expected
    "<" -> badCompRight localizer "<" tipe expected
    ">" -> badCompRight localizer ">" tipe expected
    "<=" -> badCompRight localizer "<=" tipe expected
    ">=" -> badCompRight localizer ">=" tipe expected
    "==" -> badEquality localizer "==" tipe expected
    "/=" -> badEquality localizer "/=" tipe expected
    "::" -> badConsRight localizer category tipe expected
    "++" -> badAppendRight localizer category tipe expected
    "<|" ->
      EmphRight
        ( Doc.reflow "I cannot send this through the (<|) pipe:",
          typeComparison
            localizer
            tipe
            expected
            "The argument is:"
            "But (<|) is piping it to a function that expects:"
            []
        )
    "|>" ->
      case (tipe, expected) of
        (TypeErr.Lambda expectedArgType _ _, TypeErr.Lambda argType _ _) ->
          EmphRight
            ( Doc.reflow "This function cannot handle the argument sent through the (|>) pipe:",
              typeComparison
                localizer
                argType
                expectedArgType
                "The argument is:"
                "But (|>) is piping it to a function that expects:"
                []
            )
        _ ->
          EmphRight
            ( Doc.reflow "The right side of (|>) needs to be a function so I can pipe arguments to it!",
              loneType
                localizer
                tipe
                expected
                (Doc.reflow (addCategory "But instead of a function, I am seeing" category))
                []
            )
    _ ->
      badOpRightFallback localizer category op tipe expected

badOpRightFallback :: Localizer.Localizer -> Category -> Name.Name -> TypeErr.Type -> TypeErr.Type -> RightDocs
badOpRightFallback localizer category op tipe expected =
  EmphRight
    ( Doc.reflow $
        "The right argument of (" <> Name.toChars op <> ") is causing problems.",
      typeComparison
        localizer
        tipe
        expected
        (addCategory "The right argument is" category)
        ("But (" <> Name.toChars op <> ") needs the right argument to be:")
        [ Doc.toSimpleHint
            ( "With operators like ("
                <> ( Name.toChars op
                       <> ") I always check the left\
                          \ side first. If it seems fine, I assume it is correct and check the right\
                          \ side. So the problem may be in how the left and right arguments interact!"
                   )
            )
        ]
    )

isInt :: TypeErr.Type -> Bool
isInt tipe =
  case tipe of
    TypeErr.Type home name [] ->
      TypeErr.isInt home name
    _ ->
      False

isFloat :: TypeErr.Type -> Bool
isFloat tipe =
  case tipe of
    TypeErr.Type home name [] ->
      TypeErr.isFloat home name
    _ ->
      False

isString :: TypeErr.Type -> Bool
isString tipe =
  case tipe of
    TypeErr.Type home name [] ->
      TypeErr.isString home name
    _ ->
      False

isList :: TypeErr.Type -> Bool
isList tipe =
  case tipe of
    TypeErr.Type home name [_] ->
      TypeErr.isList home name
    _ ->
      False

-- BAD CONS

badConsRight :: Localizer.Localizer -> Category -> TypeErr.Type -> TypeErr.Type -> RightDocs
badConsRight localizer category tipe expected =
  case tipe of
    TypeErr.Type home1 name1 [actualElement] | TypeErr.isList home1 name1 ->
      case expected of
        TypeErr.Type home2 name2 [expectedElement]
          | TypeErr.isList home2 name2 ->
            EmphBoth
              ( Doc.reflow "I am having trouble with this (::) operator:",
                typeComparison
                  localizer
                  expectedElement
                  actualElement
                  "The left side of (::) is:"
                  "But you are trying to put that into a list filled with:"
                  ( case expectedElement of
                      TypeErr.Type home name [_]
                        | TypeErr.isList home name ->
                          [ Doc.toSimpleHint
                              "Are you trying to append two lists? The (++) operator\
                              \ appends lists, whereas the (::) operator is only for\
                              \ adding ONE element to a list."
                          ]
                      _ ->
                        [ Doc.reflow
                            "Lists need ALL elements to be the same type though."
                        ]
                  )
              )
        _ ->
          badOpRightFallback localizer category "::" tipe expected
    _ ->
      EmphRight
        ( Doc.reflow "The (::) operator can only add elements onto lists.",
          loneType
            localizer
            tipe
            expected
            (Doc.reflow (addCategory "The right side is" category))
            [ Doc.fillSep ["But", "(::)", "needs", "a", Doc.dullyellow "List", "on", "the", "right."]
            ]
        )

-- BAD APPEND

data AppendType
  = ANumber Doc.Doc Doc.Doc
  | AString
  | AList
  | AOther

toAppendType :: TypeErr.Type -> AppendType
toAppendType tipe =
  case tipe of
    TypeErr.Type home name _
      | TypeErr.isInt home name -> ANumber "Int" "String.fromInt"
      | TypeErr.isFloat home name -> ANumber "Float" "String.fromFloat"
      | TypeErr.isString home name -> AString
      | TypeErr.isList home name -> AList
    TypeErr.FlexSuper TypeErr.Number _ -> ANumber "number" "String.fromInt"
    _ -> AOther

badAppendLeft :: Localizer.Localizer -> Category -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badAppendLeft localizer category tipe expected =
  case toAppendType tipe of
    ANumber thing stringFromThing ->
      ( Doc.fillSep
          [ "The",
            "(++)",
            "operator",
            "can",
            "append",
            "List",
            "and",
            "String",
            "values,",
            "but",
            "not",
            Doc.dullyellow thing,
            "values",
            "like",
            "this:"
          ],
        Doc.fillSep
          [ "Try",
            "using",
            Doc.green stringFromThing,
            "to",
            "turn",
            "it",
            "into",
            "a",
            "string?",
            "Or",
            "put",
            "it",
            "in",
            "[]",
            "to",
            "make",
            "it",
            "a",
            "list?",
            "Or",
            "switch",
            "to",
            "the",
            "(::)",
            "operator?"
          ]
      )
    _ ->
      ( Doc.reflow "The (++) operator cannot append this type of value:",
        loneType
          localizer
          tipe
          expected
          (Doc.reflow (addCategory "I am seeing" category))
          [ Doc.fillSep
              [ "But",
                "the",
                "(++)",
                "operator",
                "is",
                "only",
                "for",
                "appending",
                Doc.dullyellow "List",
                "and",
                Doc.dullyellow "String",
                "values.",
                "Maybe",
                "put",
                "this",
                "value",
                "in",
                "[]",
                "to",
                "make",
                "it",
                "a",
                "list?"
              ]
          ]
      )

badAppendRight :: Localizer.Localizer -> Category -> TypeErr.Type -> TypeErr.Type -> RightDocs
badAppendRight localizer category tipe expected =
  case (toAppendType expected, toAppendType tipe) of
    (AString, ANumber thing stringFromThing) ->
      EmphRight
        ( Doc.fillSep
            [ "I",
              "thought",
              "I",
              "was",
              "appending",
              Doc.dullyellow "String",
              "values",
              "here,",
              "not",
              Doc.dullyellow thing,
              "values",
              "like",
              "this:"
            ],
          Doc.fillSep
            ["Try", "using", Doc.green stringFromThing, "to", "turn", "it", "into", "a", "string?"]
        )
    (AList, ANumber thing _) ->
      EmphRight
        ( Doc.fillSep
            [ "I",
              "thought",
              "I",
              "was",
              "appending",
              Doc.dullyellow "List",
              "values",
              "here,",
              "not",
              Doc.dullyellow thing,
              "values",
              "like",
              "this:"
            ],
          Doc.reflow "Try putting it in [] to make it a list?"
        )
    (AString, AList) ->
      EmphBoth
        ( Doc.reflow "The (++) operator needs the same type of value on both sides:",
          Doc.fillSep
            [ "I",
              "see",
              "a",
              Doc.dullyellow "String",
              "on",
              "the",
              "left",
              "and",
              "a",
              Doc.dullyellow "List",
              "on",
              "the",
              "right.",
              "Which",
              "should",
              "it",
              "be?",
              "Does",
              "the",
              "string",
              "need",
              "[]",
              "around",
              "it",
              "to",
              "become",
              "a",
              "list?"
            ]
        )
    (AList, AString) ->
      EmphBoth
        ( Doc.reflow "The (++) operator needs the same type of value on both sides:",
          Doc.fillSep
            [ "I",
              "see",
              "a",
              Doc.dullyellow "List",
              "on",
              "the",
              "left",
              "and",
              "a",
              Doc.dullyellow "String",
              "on",
              "the",
              "right.",
              "Which",
              "should",
              "it",
              "be?",
              "Does",
              "the",
              "string",
              "need",
              "[]",
              "around",
              "it",
              "to",
              "become",
              "a",
              "list?"
            ]
        )
    (_, _) ->
      EmphBoth
        ( Doc.reflow "The (++) operator cannot append these two values:",
          typeComparison
            localizer
            expected
            tipe
            "I already figured out that the left side of (++) is:"
            (addCategory "But this clashes with the right side, which is" category)
            []
        )

-- BAD MATH

data ThisThenThat = FloatInt | IntFloat

badCast :: Name.Name -> ThisThenThat -> RightDocs
badCast op thisThenThat =
  EmphBoth
    ( Doc.reflow $
        "I need both sides of (" <> Name.toChars op <> ") to be the exact same type. Both Int or both Float.",
      let anInt = ["an", Doc.dullyellow "Int"]
          aFloat = ["a", Doc.dullyellow "Float"]
          toFloat = Doc.green "toFloat"
          round = Doc.green "round"
       in case thisThenThat of
            FloatInt ->
              badCastHelp aFloat anInt round toFloat
            IntFloat ->
              badCastHelp anInt aFloat toFloat round
    )

badCastHelp :: [Doc.Doc] -> [Doc.Doc] -> Doc.Doc -> Doc.Doc -> Doc.Doc
badCastHelp anInt aFloat toFloat round =
  Doc.stack
    [ Doc.fillSep (["But", "I", "see"] <> (anInt <> (["on", "the", "left", "and"] <> (aFloat <> ["on", "the", "right."])))),
      Doc.fillSep
        [ "Use",
          toFloat,
          "on",
          "the",
          "left",
          "(or",
          round,
          "on",
          "the",
          "right)",
          "to",
          "make",
          "both",
          "sides",
          "match!"
        ],
      Doc.link "Note" "Read" "implicit-casts" "to learn why Canopy does not implicitly convert Ints to Floats."
    ]

badStringAdd :: (Doc.Doc, Doc.Doc)
badStringAdd =
  ( Doc.fillSep ["I", "cannot", "do", "addition", "with", Doc.dullyellow "String", "values", "like", "this", "one:"],
    Doc.stack
      [ Doc.fillSep
          [ "The",
            "(+)",
            "operator",
            "only",
            "works",
            "with",
            Doc.dullyellow "Int",
            "and",
            Doc.dullyellow "Float",
            "values."
          ],
        Doc.toFancyHint
          [ "Switch",
            "to",
            "the",
            Doc.green "(++)",
            "operator",
            "to",
            "append",
            "strings!"
          ]
      ]
  )

badListAdd :: Localizer.Localizer -> Category -> String -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badListAdd localizer category direction tipe expected =
  ( "I cannot do addition with lists:",
    loneType
      localizer
      tipe
      expected
      (Doc.reflow (addCategory ("The " <> direction <> " side of (+) is") category))
      [ Doc.fillSep
          [ "But",
            "(+)",
            "only",
            "works",
            "with",
            Doc.dullyellow "Int",
            "and",
            Doc.dullyellow "Float",
            "values."
          ],
        Doc.toFancyHint
          [ "Switch",
            "to",
            "the",
            Doc.green "(++)",
            "operator",
            "to",
            "append",
            "lists!"
          ]
      ]
  )

badListMul :: Localizer.Localizer -> Category -> String -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badListMul localizer category direction tipe expected =
  badMath
    localizer
    category
    "Multiplication"
    direction
    "*"
    tipe
    expected
    [ Doc.toFancyHint
        [ "Maybe",
          "you",
          "want",
          Doc.green "List.repeat",
          "to",
          "build",
          "a",
          "list",
          "of",
          "repeated",
          "values?"
        ]
    ]

badMath :: Localizer.Localizer -> Category -> String -> String -> String -> TypeErr.Type -> TypeErr.Type -> [Doc.Doc] -> (Doc.Doc, Doc.Doc)
badMath localizer category operation direction op tipe expected otherHints =
  ( Doc.reflow (operation <> " does not work with this value:"),
    loneType
      localizer
      tipe
      expected
      (Doc.reflow (addCategory ("The " <> direction <> " side of (" <> op <> ") is") category))
      ( [ Doc.fillSep
            [ "But",
              "(" <> Doc.fromChars op <> ")",
              "only",
              "works",
              "with",
              Doc.dullyellow "Int",
              "and",
              Doc.dullyellow "Float",
              "values."
            ]
        ]
          <> otherHints
      )
  )

badFDiv :: Localizer.Localizer -> Doc.Doc -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badFDiv localizer direction tipe expected =
  ( Doc.reflow "The (/) operator is specifically for floating-point division:",
    if isInt tipe
      then
        Doc.stack
          [ Doc.fillSep
              [ "The",
                direction,
                "side",
                "of",
                "(/)",
                "must",
                "be",
                "a",
                Doc.dullyellow "Float" <> ",",
                "but",
                "I",
                "am",
                "seeing",
                "an",
                Doc.dullyellow "Int" <> ".",
                "I",
                "recommend:"
              ],
            Doc.vcat
              [ Doc.green "toFloat" <> " for explicit conversions     " <> Doc.black "(toFloat 5 / 2) == 2.5",
                Doc.green "(//)   " <> " for integer division         " <> Doc.black "(5 // 2)        == 2"
              ],
            Doc.link "Note" "Read" "implicit-casts" "to learn why Canopy does not implicitly convert Ints to Floats."
          ]
      else
        loneType
          localizer
          tipe
          expected
          ( Doc.fillSep
              [ "The",
                direction,
                "side",
                "of",
                "(/)",
                "must",
                "be",
                "a",
                Doc.dullyellow "Float" <> ",",
                "but",
                "instead",
                "I",
                "am",
                "seeing:"
              ]
          )
          []
  )

badIDiv :: Localizer.Localizer -> Doc.Doc -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badIDiv localizer direction tipe expected =
  ( Doc.reflow "The (//) operator is specifically for integer division:",
    if isFloat tipe
      then
        Doc.stack
          [ Doc.fillSep
              [ "The",
                direction,
                "side",
                "of",
                "(//)",
                "must",
                "be",
                "an",
                Doc.dullyellow "Int" <> ",",
                "but",
                "I",
                "am",
                "seeing",
                "a",
                Doc.dullyellow "Float" <> ".",
                "I",
                "recommend",
                "doing",
                "the",
                "conversion",
                "explicitly",
                "with",
                "one",
                "of",
                "these",
                "functions:"
              ],
            Doc.vcat
              [ Doc.green "round" <> " 3.5     == 4",
                Doc.green "floor" <> " 3.5     == 3",
                Doc.green "ceiling" <> " 3.5   == 4",
                Doc.green "truncate" <> " 3.5  == 3"
              ],
            Doc.link "Note" "Read" "implicit-casts" "to learn why Canopy does not implicitly convert Ints to Floats."
          ]
      else
        loneType
          localizer
          tipe
          expected
          ( Doc.fillSep
              [ "The",
                direction,
                "side",
                "of",
                "(//)",
                "must",
                "be",
                "an",
                Doc.dullyellow "Int" <> ",",
                "but",
                "instead",
                "I",
                "am",
                "seeing:"
              ]
          )
          []
  )

-- BAD BOOLS

badBool :: Localizer.Localizer -> Doc.Doc -> Doc.Doc -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badBool localizer op direction tipe expected =
  ( Doc.reflow "I am struggling with this boolean operation:",
    loneType
      localizer
      tipe
      expected
      ( Doc.fillSep
          [ "Both",
            "sides",
            "of",
            "(" <> op <> ")",
            "must",
            "be",
            Doc.dullyellow "Bool",
            "values,",
            "but",
            "the",
            direction,
            "side",
            "is:"
          ]
      )
      []
  )

-- BAD COMPARISON

badCompLeft :: Localizer.Localizer -> Category -> String -> String -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badCompLeft localizer category op direction tipe expected =
  ( Doc.reflow "I cannot do a comparison with this value:",
    loneType
      localizer
      tipe
      expected
      (Doc.reflow (addCategory ("The " <> direction <> " side of (" <> op <> ") is") category))
      [ Doc.fillSep
          [ "But",
            "(" <> Doc.fromChars op <> ")",
            "only",
            "works",
            "on",
            Doc.dullyellow "Int" <> ",",
            Doc.dullyellow "Float" <> ",",
            Doc.dullyellow "Char" <> ",",
            "and",
            Doc.dullyellow "String",
            "values.",
            "It",
            "can",
            "work",
            "on",
            "lists",
            "and",
            "tuples",
            "of",
            "comparable",
            "values",
            "as",
            "well,",
            "but",
            "it",
            "is",
            "usually",
            "better",
            "to",
            "find",
            "a",
            "different",
            "path."
          ]
      ]
  )

badCompRight :: Localizer.Localizer -> String -> TypeErr.Type -> TypeErr.Type -> RightDocs
badCompRight localizer op tipe expected =
  EmphBoth
    ( Doc.reflow $
        "I need both sides of (" <> op <> ") to be the same type:",
      typeComparison
        localizer
        expected
        tipe
        ("The left side of (" <> op <> ") is:")
        "But the right side is:"
        [ Doc.reflow $
            "I cannot compare different types though! Which side of (" <> op <> ") is the problem?"
        ]
    )

-- BAD EQUALITY

badEquality :: Localizer.Localizer -> String -> TypeErr.Type -> TypeErr.Type -> RightDocs
badEquality localizer op tipe expected =
  EmphBoth
    ( Doc.reflow $
        "I need both sides of (" <> op <> ") to be the same type:",
      typeComparison
        localizer
        expected
        tipe
        ("The left side of (" <> op <> ") is:")
        "But the right side is:"
        [ if isFloat tipe || isFloat expected
            then
              Doc.toSimpleNote
                "Equality on floats is not 100% reliable due to the design of IEEE 754. I\
                \ recommend a check like (abs (x - y) < 0.0001) instead."
            else Doc.reflow "Different types can never be equal though! Which side is messed up?"
        ]
    )

-- INFINITE TYPES

toInfiniteReport :: Code.Source -> Localizer.Localizer -> Ann.Region -> Name.Name -> TypeErr.Type -> Report.Report
toInfiniteReport source localizer region name overallType =
  Report.Report "INFINITE TYPE" region [] $
    Code.toSnippet
      source
      region
      Nothing
      ( Doc.reflow $
          "I am inferring a weird self-referential type for " <> Name.toChars name <> ":",
        Doc.stack
          [ Doc.reflow
              "Here is my best effort at writing down the type. You will see ∞ for\
              \ parts of the type that repeat something already printed out infinitely.",
            Doc.indent 4 (Doc.dullyellow (TypeErr.toDoc localizer RT.None overallType)),
            Doc.reflowLink
              "Staring at this type is usually not so helpful, so I recommend reading the hints at"
              "infinite-type"
              "to get unstuck!"
          ]
      )
