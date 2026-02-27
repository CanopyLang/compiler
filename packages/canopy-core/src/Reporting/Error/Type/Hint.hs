{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Type.Hint - Hint docs for type-variable constraint failures
--
-- This module provides the hint/suggestion 'Doc' values that appear at the
-- bottom of type-mismatch messages when the solver identifies a specific
-- sub-problem (e.g. Int/Float clash, rigid type-variable conflict, missing
-- record field).  All functions return '[Doc.Doc]' so callers can append them
-- to the main message with @<>@.
--
-- The functions in this module take only primitive arguments (localizer,
-- 'TypeErr.Type', 'TypeErr.Super', 'Name.Name', etc.) and have no dependency
-- on the parent 'Reporting.Error.Type' module, making circular imports
-- impossible.
module Reporting.Error.Type.Hint
  ( -- * Entry point
    problemsToHint,
    problemToHint,

    -- * Rigid type-variable hints
    badRigidVar,
    badDoubleRigid,

    -- * Super-type hints
    toASuperThing,
    badFlexSuper,
    badRigidSuper,
    badFlexFlexSuper,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Reporting.Doc as Doc
import qualified Reporting.Suggest as Suggest
import qualified Type.Error as TypeErr

-- | Convert the first problem in a list to hint docs.
--
-- Returns '[]' when the list is empty. Only the first problem is used because
-- multiple problems are usually symptoms of the same root cause and showing
-- all of them is noisy.
problemsToHint :: [TypeErr.Problem] -> [Doc.Doc]
problemsToHint problems =
  case problems of
    [] -> []
    problem : _ -> problemToHint problem

-- | Map a single 'TypeErr.Problem' to a list of hint 'Doc' values.
--
-- Each 'Problem' variant maps to zero or more actionable hints. The hints
-- are appended after the main type-comparison section of an error message.
problemToHint :: TypeErr.Problem -> [Doc.Doc]
problemToHint problem =
  case problem of
    TypeErr.IntFloat -> hintIntFloat
    TypeErr.StringFromInt -> hintStringFromInt
    TypeErr.StringFromFloat -> hintStringFromFloat
    TypeErr.StringToInt -> hintStringToInt
    TypeErr.StringToFloat -> hintStringToFloat
    TypeErr.AnythingToBool -> hintAnythingToBool
    TypeErr.AnythingFromMaybe -> hintAnythingFromMaybe
    TypeErr.ArityMismatch x y -> hintArityMismatch x y
    TypeErr.BadFlexSuper direction super _ tipe -> hintBadFlexSuper direction super tipe
    TypeErr.BadRigidVar x tipe -> hintBadRigidVar x tipe
    TypeErr.BadRigidSuper super x tipe -> hintBadRigidSuper super x tipe
    TypeErr.FieldsMissing fields -> hintFieldsMissing fields
    TypeErr.FieldTypo typo possibilities -> hintFieldTypo typo possibilities

hintIntFloat :: [Doc.Doc]
hintIntFloat =
  [ Doc.fancyLink
      "Note"
      ["Read"]
      "implicit-casts"
      [ "to", "learn", "why", "Canopy", "does", "not", "implicitly",
        "convert", "Ints", "to", "Floats.", "Use",
        Doc.green "toFloat", "and", Doc.green "round",
        "to", "do", "explicit", "conversions."
      ]
  ]

hintStringFromInt :: [Doc.Doc]
hintStringFromInt =
  [ Doc.toFancyHint
      [ "Want", "to", "convert", "an", "Int", "into", "a", "String?",
        "Use", "the", Doc.green "String.fromInt", "function!"
      ]
  ]

hintStringFromFloat :: [Doc.Doc]
hintStringFromFloat =
  [ Doc.toFancyHint
      [ "Want", "to", "convert", "a", "Float", "into", "a", "String?",
        "Use", "the", Doc.green "String.fromFloat", "function!"
      ]
  ]

hintStringToInt :: [Doc.Doc]
hintStringToInt =
  [ Doc.toFancyHint
      [ "Want", "to", "convert", "a", "String", "into", "an", "Int?",
        "Use", "the", Doc.green "String.toInt", "function!"
      ]
  ]

hintStringToFloat :: [Doc.Doc]
hintStringToFloat =
  [ Doc.toFancyHint
      [ "Want", "to", "convert", "a", "String", "into", "a", "Float?",
        "Use", "the", Doc.green "String.toFloat", "function!"
      ]
  ]

hintAnythingToBool :: [Doc.Doc]
hintAnythingToBool =
  [ Doc.toSimpleHint
      "Canopy does not have \8220truthiness\8221 such that ints and strings and lists\
      \ are automatically converted to booleans. Do that conversion explicitly!"
  ]

hintAnythingFromMaybe :: [Doc.Doc]
hintAnythingFromMaybe =
  [ Doc.toFancyHint
      [ "Use", Doc.green "Maybe.withDefault", "to", "handle", "possible", "errors.",
        "Longer", "term,", "it", "is", "usually", "better", "to", "write",
        "out", "the", "full", "`case`", "though!"
      ]
  ]

hintArityMismatch :: Int -> Int -> [Doc.Doc]
hintArityMismatch x y =
  [ Doc.toSimpleHint $
      if x < y
        then "It looks like it takes too few arguments. I was expecting " <> show (y - x) <> " more."
        else "It looks like it takes too many arguments. I see " <> show (x - y) <> " extra."
  ]

hintBadFlexSuper :: TypeErr.Direction -> TypeErr.Super -> TypeErr.Type -> [Doc.Doc]
hintBadFlexSuper direction super tipe =
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

hintBadRigidVar :: Name.Name -> TypeErr.Type -> [Doc.Doc]
hintBadRigidVar x tipe =
  case tipe of
    TypeErr.Lambda {} -> badRigidVar x "a function"
    TypeErr.Infinite -> []
    TypeErr.Error -> []
    TypeErr.FlexVar _ -> []
    TypeErr.FlexSuper s _ -> badRigidVar x (toASuperThing s)
    TypeErr.RigidVar y -> badDoubleRigid x y
    TypeErr.RigidSuper _ y -> badDoubleRigid x y
    TypeErr.Type _ n _ -> badRigidVar x ("a `" <> Name.toChars n <> "` value")
    TypeErr.Record _ _ -> badRigidVar x "a record"
    TypeErr.Unit -> badRigidVar x "a unit value"
    TypeErr.Tuple {} -> badRigidVar x "a tuple"
    TypeErr.Alias _ n _ _ -> badRigidVar x ("a `" <> Name.toChars n <> "` value")

hintBadRigidSuper :: TypeErr.Super -> Name.Name -> TypeErr.Type -> [Doc.Doc]
hintBadRigidSuper super x tipe =
  case tipe of
    TypeErr.Lambda {} -> badRigidSuper super "a function"
    TypeErr.Infinite -> []
    TypeErr.Error -> []
    TypeErr.FlexVar _ -> []
    TypeErr.FlexSuper s _ -> badRigidSuper super (toASuperThing s)
    TypeErr.RigidVar y -> badDoubleRigid x y
    TypeErr.RigidSuper _ y -> badDoubleRigid x y
    TypeErr.Type _ n _ -> badRigidSuper super ("a `" <> Name.toChars n <> "` value")
    TypeErr.Record _ _ -> badRigidSuper super "a record"
    TypeErr.Unit -> badRigidSuper super "a unit value"
    TypeErr.Tuple {} -> badRigidSuper super "a tuple"
    TypeErr.Alias _ n _ _ -> badRigidSuper super ("a `" <> Name.toChars n <> "` value")

hintFieldsMissing :: [Name.Name] -> [Doc.Doc]
hintFieldsMissing fields =
  case fmap (Doc.green . Doc.fromName) fields of
    [] -> []
    [f1] ->
      [ Doc.toFancyHint ["Looks", "like", "the", f1, "field", "is", "missing."]
      ]
    fieldDocs ->
      [ Doc.toFancyHint
          (["Looks", "like", "fields"] <> Doc.commaSep "and" id fieldDocs <> ["are", "missing."])
      ]

hintFieldTypo :: Name.Name -> [Name.Name] -> [Doc.Doc]
hintFieldTypo typo possibilities =
  case Suggest.sort (Name.toChars typo) Name.toChars possibilities of
    [] -> []
    nearest : _ ->
      [ Doc.toFancyHint
          [ "Seems", "like", "a", "record", "field", "typo.", "Maybe",
            Doc.dullyellow (Doc.fromName typo), "should", "be",
            Doc.green (Doc.fromName nearest) <> "?"
          ],
        Doc.toSimpleHint
          "Can more type annotations be added? Type annotations always help me give\
          \ more specific messages, and I think they could help a lot in this case!"
      ]

-- | Hint doc for a rigid type variable conflicting with a concrete type.
--
-- Suggests either tightening the annotation or generalising the code.
badRigidVar :: Name.Name -> String -> [Doc.Doc]
badRigidVar name aThing =
  [ Doc.toSimpleHint
      ( "Your type annotation uses type variable `"
          <> Name.toChars name
          <> "` which means ANY type of value can flow through, but your code is saying it specifically wants "
          <> aThing
          <> ". Maybe change your type annotation to be more specific? Maybe change the code to be more general?"
      ),
    Doc.reflowLink "Read" "type-annotations" "for more advice!"
  ]

-- | Hint doc for two different rigid type variables that are forced equal.
badDoubleRigid :: Name.Name -> Name.Name -> [Doc.Doc]
badDoubleRigid x y =
  [ Doc.toSimpleHint
      ( "Your type annotation uses `"
          <> Name.toChars x
          <> "` and `"
          <> Name.toChars y
          <> "` as separate type variables. Your code seems to be saying they are the\
             \ same though. Maybe they should be the same in your type annotation?\
             \ Maybe your code uses them in a weird way?"
      ),
    Doc.reflowLink "Read" "type-annotations" "for more advice!"
  ]

-- | Render a super-type constraint name as an English noun phrase.
--
-- Used to build sentences like "your code specifically wants a \`number\` value".
toASuperThing :: TypeErr.Super -> String
toASuperThing super =
  case super of
    TypeErr.Number -> "a `number` value"
    TypeErr.Comparable -> "a `comparable` value"
    TypeErr.CompAppend -> "a `compappend` value"
    TypeErr.Appendable -> "an `appendable` value"

-- | Hint docs when a flex super-type (e.g. @number@) is unified with an
-- incompatible concrete type.
badFlexSuper :: TypeErr.Direction -> TypeErr.Super -> TypeErr.Type -> [Doc.Doc]
badFlexSuper direction super tipe =
  case super of
    TypeErr.Comparable -> badComparableHint tipe
    TypeErr.Appendable ->
      [ Doc.toSimpleHint "I only know how to append strings and lists."
      ]
    TypeErr.CompAppend ->
      [ Doc.toSimpleHint "Only strings and lists are both comparable and appendable."
      ]
    TypeErr.Number -> badNumberHint direction tipe

badComparableHint :: TypeErr.Type -> [Doc.Doc]
badComparableHint tipe =
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
              <> Name.toChars name
              <> "` values. I can only\
                 \ compare ints, floats, chars, strings, lists of comparable values, and tuples\
                 \ of comparable values."
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

badNumberHint :: TypeErr.Direction -> TypeErr.Type -> [Doc.Doc]
badNumberHint direction tipe =
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

-- | Hint docs when a rigid super-type variable (e.g. @number@) is unified
-- with an incompatible concrete type.
badRigidSuper :: TypeErr.Super -> String -> [Doc.Doc]
badRigidSuper super aThing =
  let (superType, manyThings) = superDescription super
   in [ Doc.toSimpleHint
          ( "The `"
              <> superType
              <> "` in your type annotation is saying that "
              <> manyThings
              <> " can flow through, but your code is saying it specifically wants "
              <> aThing
              <> ". Maybe change your type annotation to be more specific? Maybe change the code to be more general?"
          ),
        Doc.reflowLink "Read" "type-annotations" "for more advice!"
      ]

superDescription :: TypeErr.Super -> (String, String)
superDescription super =
  case super of
    TypeErr.Number -> ("number", "ints AND floats")
    TypeErr.Comparable -> ("comparable", "ints, floats, chars, strings, lists, and tuples")
    TypeErr.Appendable -> ("appendable", "strings AND lists")
    TypeErr.CompAppend -> ("compappend", "strings AND lists")

-- | Hint docs when two flex super-types are unified but are incompatible.
badFlexFlexSuper :: TypeErr.Super -> TypeErr.Super -> [Doc.Doc]
badFlexFlexSuper s1 s2 =
  [ Doc.toSimpleHint
      ("There are no values in Canopy that are both " <> likeThis s1 <> " and " <> likeThis s2 <> ".")
  ]
  where
    likeThis super =
      case super of
        TypeErr.Number -> "a number"
        TypeErr.Comparable -> "comparable"
        TypeErr.CompAppend -> "a compappend"
        TypeErr.Appendable -> "appendable"
