{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Type.Operators - Category types and operator error message helpers
--
-- This module provides:
--
--   * The 'Category', 'PCategory', and 'MaybeName' types that classify what
--     kind of expression or pattern is involved in a type mismatch.
--   * 'addCategory' and 'addPatternCategory' for building "it is a …" strings.
--   * The message-building functions for type errors involving binary operators.
--
-- The parent module 'Reporting.Error.Type' re-exports all types from here so
-- that downstream callers ('Type.Constrain.Expression', 'Type.Solve', etc.)
-- do not need to change their import paths.
module Reporting.Error.Type.Operators
  ( -- * Expression category
    Category (..),
    MaybeName (..),
    addCategory,

    -- * Pattern category
    PCategory (..),
    addPatternCategory,

    -- * Operator error docs
    RightDocs (..),
    opLeftToDocs,
    opRightToDocs,

    -- * Type-classification predicates
    isInt,
    isFloat,
    isString,
    isList,

    -- * Cons / append helpers
    badConsRight,
    AppendType (..),
    toAppendType,
    badAppendLeft,
    badAppendRight,

    -- * Math / division helpers
    ThisThenThat (..),
    badCast,
    badStringAdd,
    badListAdd,
    badListMul,
    badMath,
    badFDiv,
    badIDiv,

    -- * Bool / comparison / equality helpers
    badBool,
    badCompLeft,
    badCompRight,
    badEquality,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Type.Error as TypeErr

-- ---------------------------------------------------------------------------
-- Category / MaybeName / PCategory types
-- ---------------------------------------------------------------------------

-- | Classifies what kind of expression is involved in a type mismatch.
--
-- Used to generate "it is a list" / "this call produces" phrases in messages.
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

-- | An optional name for the function/constructor/operator in a call.
data MaybeName
  = FuncName Name.Name
  | CtorName Name.Name
  | OpName Name.Name
  | NoName
  deriving (Show)

-- | Build a sentence fragment that names the expression category.
--
-- @addCategory "It is" List@ → @"It is a list of type:"@
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

-- | Classifies what kind of pattern is involved in a pattern type mismatch.
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

-- | Build a sentence fragment that names the pattern category.
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

-- ---------------------------------------------------------------------------
-- RightDocs
-- ---------------------------------------------------------------------------

-- | Distinguishes emphasis mode for right-side operator errors.
--
-- 'EmphBoth' is used when both sides of the operator contribute to the
-- problem (e.g. mismatched types on @(++)@). 'EmphRight' is used when only
-- the right side needs to be highlighted.
data RightDocs
  = EmphBoth (Doc.Doc, Doc.Doc)
  | EmphRight (Doc.Doc, Doc.Doc)

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

-- | Build the @(title, body)@ doc pair for a left-side operator error.
opLeftToDocs ::
  Localizer.Localizer ->
  Category ->
  Name.Name ->
  TypeErr.Type ->
  TypeErr.Type ->
  (Doc.Doc, Doc.Doc)
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
          [Doc.reflow "This needs to be some kind of function though!"]
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

-- | Build the 'RightDocs' for a right-side operator error.
opRightToDocs ::
  Localizer.Localizer ->
  Category ->
  Name.Name ->
  TypeErr.Type ->
  TypeErr.Type ->
  RightDocs
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
      | otherwise -> EmphRight $ badMath localizer category "Subtraction" "right" "-" tipe expected []
    "^"
      | isFloat expected && isInt tipe -> badCast op FloatInt
      | isInt expected && isFloat tipe -> badCast op IntFloat
      | otherwise -> EmphRight $ badMath localizer category "Exponentiation" "right" "^" tipe expected []
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
    "|>" -> opPipeRight localizer category tipe expected
    _ -> badOpRightFallback localizer category op tipe expected

opPipeRight :: Localizer.Localizer -> Category -> TypeErr.Type -> TypeErr.Type -> RightDocs
opPipeRight localizer category tipe expected =
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

badOpRightFallback ::
  Localizer.Localizer ->
  Category ->
  Name.Name ->
  TypeErr.Type ->
  TypeErr.Type ->
  RightDocs
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
                <> Name.toChars op
                <> ") I always check the left\
                   \ side first. If it seems fine, I assume it is correct and check the right\
                   \ side. So the problem may be in how the left and right arguments interact!"
            )
        ]
    )

-- ---------------------------------------------------------------------------
-- Type predicates
-- ---------------------------------------------------------------------------

-- | True if the type is a concrete @Int@.
isInt :: TypeErr.Type -> Bool
isInt tipe =
  case tipe of
    TypeErr.Type home name [] -> TypeErr.isInt home name
    _ -> False

-- | True if the type is a concrete @Float@.
isFloat :: TypeErr.Type -> Bool
isFloat tipe =
  case tipe of
    TypeErr.Type home name [] -> TypeErr.isFloat home name
    _ -> False

-- | True if the type is a concrete @String@.
isString :: TypeErr.Type -> Bool
isString tipe =
  case tipe of
    TypeErr.Type home name [] -> TypeErr.isString home name
    _ -> False

-- | True if the type is a @List a@ (exactly one type argument).
isList :: TypeErr.Type -> Bool
isList tipe =
  case tipe of
    TypeErr.Type home name [_] -> TypeErr.isList home name
    _ -> False

-- ---------------------------------------------------------------------------
-- Cons (::)
-- ---------------------------------------------------------------------------

-- | Build the 'RightDocs' for a @(::)@ right-side error.
badConsRight :: Localizer.Localizer -> Category -> TypeErr.Type -> TypeErr.Type -> RightDocs
badConsRight localizer category tipe expected =
  case tipe of
    TypeErr.Type home1 name1 [actualElement] | TypeErr.isList home1 name1 ->
      consListVsList localizer category tipe actualElement expected
    _ ->
      EmphRight
        ( Doc.reflow "The (::) operator can only add elements onto lists.",
          loneType
            localizer
            tipe
            expected
            (Doc.reflow (addCategory "The right side is" category))
            [Doc.fillSep ["But", "(::)", "needs", "a", Doc.dullyellow "List", "on", "the", "right."]]
        )

consListVsList :: Localizer.Localizer -> Category -> TypeErr.Type -> TypeErr.Type -> TypeErr.Type -> RightDocs
consListVsList localizer category listTipe actualElement expected =
  case expected of
    TypeErr.Type home2 name2 [expectedElement] | TypeErr.isList home2 name2 ->
      EmphBoth
        ( Doc.reflow "I am having trouble with this (::) operator:",
          typeComparison
            localizer
            expectedElement
            actualElement
            "The left side of (::) is:"
            "But you are trying to put that into a list filled with:"
            (consHints expectedElement)
        )
    _ ->
      badOpRightFallback localizer category "::" listTipe expected

consHints :: TypeErr.Type -> [Doc.Doc]
consHints expectedElement =
  case expectedElement of
    TypeErr.Type home name [_] | TypeErr.isList home name ->
      [ Doc.toSimpleHint
          "Are you trying to append two lists? The (++) operator\
          \ appends lists, whereas the (::) operator is only for\
          \ adding ONE element to a list."
      ]
    _ ->
      [Doc.reflow "Lists need ALL elements to be the same type though."]

-- ---------------------------------------------------------------------------
-- Append (++)
-- ---------------------------------------------------------------------------

-- | Classify a type for append-operator messages.
data AppendType
  = ANumber Doc.Doc Doc.Doc
  | AString
  | AList
  | AOther

-- | Classify a 'TypeErr.Type' for append-operator messages.
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

-- | Error message for the left side of @(++)@.
badAppendLeft :: Localizer.Localizer -> Category -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badAppendLeft localizer category tipe expected =
  case toAppendType tipe of
    ANumber thing stringFromThing ->
      ( Doc.fillSep
          [ "The", "(++)", "operator", "can", "append", "List", "and", "String",
            "values,", "but", "not", Doc.dullyellow thing, "values", "like", "this:"
          ],
        Doc.fillSep
          [ "Try", "using", Doc.green stringFromThing, "to", "turn", "it", "into",
            "a", "string?", "Or", "put", "it", "in", "[]", "to", "make", "it", "a",
            "list?", "Or", "switch", "to", "the", "(::)", "operator?"
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
              [ "But", "the", "(++)", "operator", "is", "only", "for", "appending",
                Doc.dullyellow "List", "and", Doc.dullyellow "String", "values.",
                "Maybe", "put", "this", "value", "in", "[]", "to", "make", "it", "a", "list?"
              ]
          ]
      )

-- | Error message for the right side of @(++)@.
badAppendRight :: Localizer.Localizer -> Category -> TypeErr.Type -> TypeErr.Type -> RightDocs
badAppendRight localizer category tipe expected =
  case (toAppendType expected, toAppendType tipe) of
    (AString, ANumber thing stringFromThing) ->
      EmphRight
        ( Doc.fillSep
            [ "I", "thought", "I", "was", "appending", Doc.dullyellow "String",
              "values", "here,", "not", Doc.dullyellow thing, "values", "like", "this:"
            ],
          Doc.fillSep ["Try", "using", Doc.green stringFromThing, "to", "turn", "it", "into", "a", "string?"]
        )
    (AList, ANumber thing _) ->
      EmphRight
        ( Doc.fillSep
            [ "I", "thought", "I", "was", "appending", Doc.dullyellow "List",
              "values", "here,", "not", Doc.dullyellow thing, "values", "like", "this:"
            ],
          Doc.reflow "Try putting it in [] to make it a list?"
        )
    (AString, AList) -> appendSideMismatch "String" "List"
    (AList, AString) -> appendSideMismatch "List" "String"
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

appendSideMismatch :: Doc.Doc -> Doc.Doc -> RightDocs
appendSideMismatch leftType rightType =
  EmphBoth
    ( Doc.reflow "The (++) operator needs the same type of value on both sides:",
      Doc.fillSep
        [ "I", "see", "a", Doc.dullyellow leftType, "on", "the", "left", "and", "a",
          Doc.dullyellow rightType, "on", "the", "right.", "Which", "should", "it", "be?",
          "Does", "the", "string", "need", "[]", "around", "it", "to", "become", "a", "list?"
        ]
    )

-- ---------------------------------------------------------------------------
-- Math operators
-- ---------------------------------------------------------------------------

-- | Direction of an Int/Float mismatch on a binary math operator.
data ThisThenThat = FloatInt | IntFloat

-- | Error for Int/Float mismatches on arithmetic operators.
badCast :: Name.Name -> ThisThenThat -> RightDocs
badCast op thisThenThat =
  EmphBoth
    ( Doc.reflow $
        "I need both sides of (" <> Name.toChars op <> ") to be the exact same type. Both Int or both Float.",
      let anInt = ["an", Doc.dullyellow "Int"]
          aFloat = ["a", Doc.dullyellow "Float"]
          toFloat = Doc.green "toFloat"
          roundFn = Doc.green "round"
       in case thisThenThat of
            FloatInt -> badCastHelp aFloat anInt roundFn toFloat
            IntFloat -> badCastHelp anInt aFloat toFloat roundFn
    )

badCastHelp :: [Doc.Doc] -> [Doc.Doc] -> Doc.Doc -> Doc.Doc -> Doc.Doc
badCastHelp anInt aFloat toFloat roundFn =
  Doc.stack
    [ Doc.fillSep (["But", "I", "see"] <> anInt <> ["on", "the", "left", "and"] <> aFloat <> ["on", "the", "right."]),
      Doc.fillSep
        ["Use", toFloat, "on", "the", "left", "(or", roundFn, "on", "the", "right)", "to", "make", "both", "sides", "match!"],
      Doc.link "Note" "Read" "implicit-casts" "to learn why Canopy does not implicitly convert Ints to Floats."
    ]

-- | Error for using @(+)@ on a @String@.
badStringAdd :: (Doc.Doc, Doc.Doc)
badStringAdd =
  ( Doc.fillSep ["I", "cannot", "do", "addition", "with", Doc.dullyellow "String", "values", "like", "this", "one:"],
    Doc.stack
      [ Doc.fillSep
          ["The", "(+)", "operator", "only", "works", "with", Doc.dullyellow "Int", "and", Doc.dullyellow "Float", "values."],
        Doc.toFancyHint ["Switch", "to", "the", Doc.green "(++)", "operator", "to", "append", "strings!"]
      ]
  )

-- | Error for using @(+)@ on a @List@.
badListAdd :: Localizer.Localizer -> Category -> String -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badListAdd localizer category direction tipe expected =
  ( "I cannot do addition with lists:",
    loneType
      localizer
      tipe
      expected
      (Doc.reflow (addCategory ("The " <> direction <> " side of (+) is") category))
      [ Doc.fillSep
          ["But", "(+)", "only", "works", "with", Doc.dullyellow "Int", "and", Doc.dullyellow "Float", "values."],
        Doc.toFancyHint ["Switch", "to", "the", Doc.green "(++)", "operator", "to", "append", "lists!"]
      ]
  )

-- | Error for using @(*)@ on a @List@.
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
        ["Maybe", "you", "want", Doc.green "List.repeat", "to", "build", "a", "list", "of", "repeated", "values?"]
    ]

-- | Generic math-operator error message.
badMath ::
  Localizer.Localizer ->
  Category ->
  String ->
  String ->
  String ->
  TypeErr.Type ->
  TypeErr.Type ->
  [Doc.Doc] ->
  (Doc.Doc, Doc.Doc)
badMath localizer category operation direction op tipe expected otherHints =
  ( Doc.reflow (operation <> " does not work with this value:"),
    loneType
      localizer
      tipe
      expected
      (Doc.reflow (addCategory ("The " <> direction <> " side of (" <> op <> ") is") category))
      ( [ Doc.fillSep
            ["But", "(" <> Doc.fromChars op <> ")", "only", "works", "with", Doc.dullyellow "Int", "and", Doc.dullyellow "Float", "values."]
        ]
          <> otherHints
      )
  )

-- | Error for using @(/)@ on a non-Float.
badFDiv :: Localizer.Localizer -> Doc.Doc -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badFDiv localizer direction tipe expected =
  ( Doc.reflow "The (/) operator is specifically for floating-point division:",
    if isInt tipe
      then fDivIntBody direction
      else
        loneType
          localizer
          tipe
          expected
          ( Doc.fillSep
              ["The", direction, "side", "of", "(/)", "must", "be", "a",
               Doc.dullyellow "Float" <> ",", "but", "instead", "I", "am", "seeing:"]
          )
          []
  )

fDivIntBody :: Doc.Doc -> Doc.Doc
fDivIntBody direction =
  Doc.stack
    [ Doc.fillSep
        [ "The", direction, "side", "of", "(/)", "must", "be", "a",
          Doc.dullyellow "Float" <> ",", "but", "I", "am", "seeing", "an",
          Doc.dullyellow "Int" <> ".", "I", "recommend:"
        ],
      Doc.vcat
        [ Doc.green "toFloat" <> " for explicit conversions     " <> Doc.black "(toFloat 5 / 2) == 2.5",
          Doc.green "(//)   " <> " for integer division         " <> Doc.black "(5 // 2)        == 2"
        ],
      Doc.link "Note" "Read" "implicit-casts" "to learn why Canopy does not implicitly convert Ints to Floats."
    ]

-- | Error for using @(//)@ on a non-Int.
badIDiv :: Localizer.Localizer -> Doc.Doc -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badIDiv localizer direction tipe expected =
  ( Doc.reflow "The (//) operator is specifically for integer division:",
    if isFloat tipe
      then iDivFloatBody direction
      else
        loneType
          localizer
          tipe
          expected
          ( Doc.fillSep
              ["The", direction, "side", "of", "(//)", "must", "be", "an",
               Doc.dullyellow "Int" <> ",", "but", "instead", "I", "am", "seeing:"]
          )
          []
  )

iDivFloatBody :: Doc.Doc -> Doc.Doc
iDivFloatBody direction =
  Doc.stack
    [ Doc.fillSep
        [ "The", direction, "side", "of", "(//)", "must", "be", "an",
          Doc.dullyellow "Int" <> ",", "but", "I", "am", "seeing", "a",
          Doc.dullyellow "Float" <> ".", "I", "recommend", "doing", "the",
          "conversion", "explicitly", "with", "one", "of", "these", "functions:"
        ],
      Doc.vcat
        [ Doc.green "round" <> " 3.5     == 4",
          Doc.green "floor" <> " 3.5     == 3",
          Doc.green "ceiling" <> " 3.5   == 4",
          Doc.green "truncate" <> " 3.5  == 3"
        ],
      Doc.link "Note" "Read" "implicit-casts" "to learn why Canopy does not implicitly convert Ints to Floats."
    ]

-- ---------------------------------------------------------------------------
-- Bool / comparison / equality
-- ---------------------------------------------------------------------------

-- | Error for using @(&&)@ or @(||)@ on a non-Bool.
badBool :: Localizer.Localizer -> Doc.Doc -> Doc.Doc -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badBool localizer op direction tipe expected =
  ( Doc.reflow "I am struggling with this boolean operation:",
    loneType
      localizer
      tipe
      expected
      ( Doc.fillSep
          ["Both", "sides", "of", "(" <> op <> ")", "must", "be",
           Doc.dullyellow "Bool", "values,", "but", "the", direction, "side", "is:"]
      )
      []
  )

-- | Error for using a comparison operator on a non-comparable type (left side).
badCompLeft :: Localizer.Localizer -> Category -> String -> String -> TypeErr.Type -> TypeErr.Type -> (Doc.Doc, Doc.Doc)
badCompLeft localizer category op direction tipe expected =
  ( Doc.reflow "I cannot do a comparison with this value:",
    loneType
      localizer
      tipe
      expected
      (Doc.reflow (addCategory ("The " <> direction <> " side of (" <> op <> ") is") category))
      [ Doc.fillSep
          [ "But", "(" <> Doc.fromChars op <> ")", "only", "works", "on",
            Doc.dullyellow "Int" <> ",", Doc.dullyellow "Float" <> ",",
            Doc.dullyellow "Char" <> ",", "and", Doc.dullyellow "String",
            "values.", "It", "can", "work", "on", "lists", "and", "tuples",
            "of", "comparable", "values", "as", "well,", "but", "it", "is",
            "usually", "better", "to", "find", "a", "different", "path."
          ]
      ]
  )

-- | Error for a comparison operator where both sides have different types.
badCompRight :: Localizer.Localizer -> String -> TypeErr.Type -> TypeErr.Type -> RightDocs
badCompRight localizer op tipe expected =
  EmphBoth
    ( Doc.reflow $ "I need both sides of (" <> op <> ") to be the same type:",
      typeComparison
        localizer
        expected
        tipe
        ("The left side of (" <> op <> ") is:")
        "But the right side is:"
        [Doc.reflow $ "I cannot compare different types though! Which side of (" <> op <> ") is the problem?"]
    )

-- | Error for @(==)@ or @(/=)@ where both sides have different types.
badEquality :: Localizer.Localizer -> String -> TypeErr.Type -> TypeErr.Type -> RightDocs
badEquality localizer op tipe expected =
  EmphBoth
    ( Doc.reflow $ "I need both sides of (" <> op <> ") to be the same type:",
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

-- ---------------------------------------------------------------------------
-- Internal doc helpers
-- ---------------------------------------------------------------------------

-- | Side-by-side type comparison doc.
typeComparison :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> String -> String -> [Doc.Doc] -> Doc.Doc
typeComparison localizer actual expected iAmSeeing insteadOf contextHints =
  let (actualDoc, expectedDoc, problems) = TypeErr.toComparison localizer actual expected
   in Doc.stack
        ( [Doc.reflow iAmSeeing, Doc.indent 4 actualDoc, Doc.reflow insteadOf, Doc.indent 4 expectedDoc]
            <> (contextHints <> problemsToHint problems)
        )

-- | Show only the actual type with a custom heading.
loneType :: Localizer.Localizer -> TypeErr.Type -> TypeErr.Type -> Doc.Doc -> [Doc.Doc] -> Doc.Doc
loneType localizer actual expected iAmSeeing furtherDetails =
  let (actualDoc, _, problems) = TypeErr.toComparison localizer actual expected
   in Doc.stack
        ([iAmSeeing, Doc.indent 4 actualDoc] <> (furtherDetails <> problemsToHint problems))

-- | Minimal 'problemsToHint' to break potential import cycles.
--
-- Only the IntFloat hint is needed inside operator messages; all other
-- hints are handled by the parent module via 'Reporting.Error.Type.Hint'.
problemsToHint :: [TypeErr.Problem] -> [Doc.Doc]
problemsToHint problems =
  case problems of
    [] -> []
    problem : _ -> problemToHint problem

problemToHint :: TypeErr.Problem -> [Doc.Doc]
problemToHint problem =
  case problem of
    TypeErr.IntFloat ->
      [ Doc.fancyLink
          "Note"
          ["Read"]
          "implicit-casts"
          [ "to", "learn", "why", "Canopy", "does", "not", "implicitly", "convert",
            "Ints", "to", "Floats.", "Use", Doc.green "toFloat", "and", Doc.green "round",
            "to", "do", "explicit", "conversions."
          ]
      ]
    _ -> []
