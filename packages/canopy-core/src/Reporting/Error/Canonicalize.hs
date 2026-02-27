{-# LANGUAGE OverloadedStrings #-}

module Reporting.Error.Canonicalize
  ( Error (..),
    BadArityContext (..),
    InvalidPayload (..),
    PortProblem (..),
    DuplicatePatternContext (..),
    PossibleNames (..),
    VarKind (..),
    toDiagnostic,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Char as Char
import qualified Data.Index as Index
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.OneOrMore as OneOrMore
import qualified Data.Set as Set
import qualified Reporting.Annotation as Ann
import Reporting.Doc (Doc, (<+>))
import qualified Reporting.Doc as Doc
import qualified Reporting.Render.Code as Code
import qualified Reporting.Render.Type as RT
import qualified Reporting.Report as Report
import qualified Reporting.Suggest as Suggest
import qualified Data.Text as Text
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..), Suggestion (..), Confidence (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.ErrorCode as EC

-- CANONICALIZATION ERRORS

data Error
  = AnnotationTooShort Ann.Region Name.Name Index.ZeroBased Int
  | AmbiguousVar Ann.Region (Maybe Name.Name) Name.Name ModuleName.Canonical (OneOrMore.OneOrMore ModuleName.Canonical)
  | AmbiguousType Ann.Region (Maybe Name.Name) Name.Name ModuleName.Canonical (OneOrMore.OneOrMore ModuleName.Canonical)
  | AmbiguousVariant Ann.Region (Maybe Name.Name) Name.Name ModuleName.Canonical (OneOrMore.OneOrMore ModuleName.Canonical)
  | AmbiguousBinop Ann.Region Name.Name ModuleName.Canonical (OneOrMore.OneOrMore ModuleName.Canonical)
  | BadArity Ann.Region BadArityContext Name.Name Int Int
  | Binop Ann.Region Name.Name Name.Name
  | DuplicateDecl Name.Name Ann.Region Ann.Region
  | DuplicateType Name.Name Ann.Region Ann.Region
  | DuplicateCtor Name.Name Ann.Region Ann.Region
  | DuplicateBinop Name.Name Ann.Region Ann.Region
  | DuplicateField Name.Name Ann.Region Ann.Region
  | DuplicateAliasArg Name.Name Name.Name Ann.Region Ann.Region
  | DuplicateUnionArg Name.Name Name.Name Ann.Region Ann.Region
  | DuplicatePattern DuplicatePatternContext Name.Name Ann.Region Ann.Region
  | EffectNotFound Ann.Region Name.Name
  | EffectFunctionNotFound Ann.Region Name.Name
  | ExportDuplicate Name.Name Ann.Region Ann.Region
  | ExportNotFound Ann.Region VarKind Name.Name [Name.Name]
  | ExportOpenAlias Ann.Region Name.Name
  | ImportCtorByName Ann.Region Name.Name Name.Name
  | ImportNotFound Ann.Region Name.Name [ModuleName.Canonical]
  | ImportOpenAlias Ann.Region Name.Name
  | ImportExposingNotFound Ann.Region ModuleName.Canonical Name.Name [Name.Name]
  | NotFoundVar Ann.Region (Maybe Name.Name) Name.Name PossibleNames
  | NotFoundType Ann.Region (Maybe Name.Name) Name.Name PossibleNames
  | NotFoundVariant Ann.Region (Maybe Name.Name) Name.Name PossibleNames
  | NotFoundBinop Ann.Region Name.Name (Set.Set Name.Name)
  | PatternHasRecordCtor Ann.Region Name.Name
  | PortPayloadInvalid Ann.Region Name.Name Can.Type InvalidPayload
  | PortTypeInvalid Ann.Region Name.Name PortProblem
  | RecursiveAlias Ann.Region Name.Name [Name.Name] Src.Type [Name.Name]
  | RecursiveDecl Ann.Region Name.Name [Name.Name]
  | RecursiveLet (Ann.Located Name.Name) [Name.Name]
  | Shadowing Name.Name Ann.Region Ann.Region
  | TupleLargerThanThree Ann.Region
  | TypeVarsUnboundInUnion Ann.Region Name.Name [Name.Name] (Name.Name, Ann.Region) [(Name.Name, Ann.Region)]
  | TypeVarsMessedUpInAlias Ann.Region Name.Name [Name.Name] [(Name.Name, Ann.Region)] [(Name.Name, Ann.Region)]
  | FFIFileNotFound Ann.Region FilePath
  | FFIFileTimeout Ann.Region FilePath Int
  | FFIParseError Ann.Region FilePath String
  | FFIPathTraversal Ann.Region FilePath String
  | FFIInvalidType Ann.Region FilePath Name.Name String
  | FFIMissingAnnotation Ann.Region FilePath Name.Name
  | FFICircularDependency Ann.Region FilePath [FilePath]
  | FFITypeNotFound Ann.Region FilePath Name.Name String [Name.Name]
  | LazyImportNotFound Ann.Region Name.Name [Name.Name]
  | LazyImportCoreModule Ann.Region Name.Name
  | LazyImportInPackage Ann.Region Name.Name
  | LazyImportSelf Ann.Region Name.Name
  | LazyImportKernel Ann.Region Name.Name
  deriving (Show)

data BadArityContext
  = TypeArity
  | PatternArity
  deriving (Show)

data DuplicatePatternContext
  = DPLambdaArgs
  | DPFuncArgs Name.Name
  | DPCaseBranch
  | DPLetBinding
  | DPDestruct
  deriving (Show)

data InvalidPayload
  = ExtendedRecord
  | Function
  | TypeVariable Name.Name
  | UnsupportedType Name.Name
  deriving (Show)

data PortProblem
  = CmdNoArg
  | CmdExtraArgs Int
  | CmdBadMsg
  | SubBad
  | NotCmdOrSub
  deriving (Show)

data PossibleNames = PossibleNames
  { _locals :: Set.Set Name.Name,
    _quals :: Map.Map Name.Name (Set.Set Name.Name)
  }
  deriving (Show)

-- KIND

data VarKind
  = BadOp
  | BadVar
  | BadPattern
  | BadType
  deriving (Show)

toKindInfo :: VarKind -> Name.Name -> (Doc, Doc, Doc)
toKindInfo kind name =
  case kind of
    BadOp ->
      ("an", "operator", "(" <> Doc.fromName name <> ")")
    BadVar ->
      ("a", "value", "`" <> Doc.fromName name <> "`")
    BadPattern ->
      ("a", "pattern", "`" <> Doc.fromName name <> "`")
    BadType ->
      ("a", "type", "`" <> Doc.fromName name <> "`")

-- TO REPORT

toReport :: Code.Source -> Error -> Report.Report
toReport source err =
  case err of
    AnnotationTooShort region name index leftovers ->
      let numTypeArgs = Index.toMachine index
          numDefArgs = numTypeArgs + leftovers
       in Report.Report "BAD TYPE ANNOTATION" region [] $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow $
                  "The type annotation for `" <> Name.toChars name <> "` says it can accept "
                    <> Doc.args numTypeArgs
                    <> ", but the definition says it has "
                    <> Doc.args numDefArgs
                    <> ":",
                Doc.reflow $
                  "Is the type annotation missing something? Should some argument"
                    <> (if leftovers == 1 then "" else "s")
                    <> " be deleted? Maybe some parentheses are missing?"
              )
    AmbiguousVar region maybePrefix name h hs ->
      ambiguousName source region maybePrefix name h hs "variable"
    AmbiguousType region maybePrefix name h hs ->
      ambiguousName source region maybePrefix name h hs "type"
    AmbiguousVariant region maybePrefix name h hs ->
      ambiguousName source region maybePrefix name h hs "variant"
    AmbiguousBinop region name h hs ->
      ambiguousName source region Nothing name h hs "operator"
    BadArity region badArityContext name expected actual ->
      let thing =
            case badArityContext of
              TypeArity -> "type"
              PatternArity -> "variant"
       in if actual < expected
            then
              Report.Report "TOO FEW ARGS" region [] $
                Code.toSnippet
                  source
                  region
                  Nothing
                  ( Doc.reflow $
                      "The `" <> Name.toChars name <> "` " <> thing <> " needs "
                        <> Doc.args expected
                        <> ", but I see "
                        <> show actual
                        <> " instead:",
                    Doc.reflow "What is missing? Are some parentheses misplaced?"
                  )
            else
              Report.Report "TOO MANY ARGS" region [] $
                Code.toSnippet
                  source
                  region
                  Nothing
                  ( Doc.reflow $
                      "The `" <> Name.toChars name <> "` " <> thing <> " needs "
                        <> Doc.args expected
                        <> ", but I see "
                        <> show actual
                        <> " instead:",
                    if actual - expected == 1
                      then "Which is the extra one? Maybe some parentheses are missing?"
                      else "Which are the extra ones? Maybe some parentheses are missing?"
                  )
    Binop region op1 op2 ->
      Report.Report "INFIX PROBLEM" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow $
              "You cannot mix (" <> Name.toChars op1 <> ") and (" <> Name.toChars op2 <> ") without parentheses.",
            Doc.reflow
              "I do not know how to group these expressions. Add parentheses for me!"
          )
    DuplicateDecl name r1 r2 ->
      nameClash source r1 r2 $
        "This file has multiple `" <> Name.toChars name <> "` declarations."
    DuplicateType name r1 r2 ->
      nameClash source r1 r2 $
        "This file defines multiple `" <> Name.toChars name <> "` types."
    DuplicateCtor name r1 r2 ->
      nameClash source r1 r2 $
        "This file defines multiple `" <> Name.toChars name <> "` type constructors."
    DuplicateBinop name r1 r2 ->
      nameClash source r1 r2 $
        "This file defines multiple (" <> Name.toChars name <> ") operators."
    DuplicateField name r1 r2 ->
      nameClash source r1 r2 $
        "This record has multiple `" <> Name.toChars name <> "` fields."
    DuplicateAliasArg typeName name r1 r2 ->
      nameClash source r1 r2 $
        "The `" <> Name.toChars typeName <> "` type alias has multiple `" <> Name.toChars name <> "` type variables."
    DuplicateUnionArg typeName name r1 r2 ->
      nameClash source r1 r2 $
        "The `" <> Name.toChars typeName <> "` type has multiple `" <> Name.toChars name <> "` type variables."
    DuplicatePattern context name r1 r2 ->
      nameClash source r1 r2 $
        case context of
          DPLambdaArgs ->
            "This anonymous function has multiple `" <> Name.toChars name <> "` arguments."
          DPFuncArgs funcName ->
            "The `" <> Name.toChars funcName <> "` function has multiple `" <> Name.toChars name <> "` arguments."
          DPCaseBranch ->
            "This `case` pattern has multiple `" <> Name.toChars name <> "` variables."
          DPLetBinding ->
            "This `let` expression defines `" <> Name.toChars name <> "` more than once!"
          DPDestruct ->
            "This pattern contains multiple `" <> Name.toChars name <> "` variables."
    EffectNotFound region name ->
      Report.Report "EFFECT PROBLEM" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow ("You have declared that `" <> (Name.toChars name <> "` is an effect type:")),
            Doc.reflow ("But I cannot find a custom type named `" <> (Name.toChars name <> "` in this file!"))
          )
    EffectFunctionNotFound region name ->
      Report.Report "EFFECT PROBLEM" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow ("This kind of effect module must define a `" <> (Name.toChars name <> "` function.")),
            Doc.reflow ("But I cannot find `" <> (Name.toChars name <> "` in this file!"))
          )
    ExportDuplicate name r1 r2 ->
      let messageThatEndsWithPunctuation =
            "You are trying to expose `" <> Name.toChars name <> "` multiple times!"
       in Report.Report "REDUNDANT EXPORT" r2 [] $
            Code.toPair
              source
              r1
              r2
              ( Doc.reflow messageThatEndsWithPunctuation,
                "Remove one of them and you should be all set!"
              )
              ( Doc.reflow (messageThatEndsWithPunctuation <> " Once here:"),
                "And again right here:",
                "Remove one of them and you should be all set!"
              )
    ExportNotFound region kind rawName possibleNames ->
      let suggestions =
            (fmap Name.toChars . take 4 $ Suggest.sort (Name.toChars rawName) Name.toChars possibleNames)
       in Report.Report "UNKNOWN EXPORT" region suggestions $
            let (a, thing, name) = toKindInfo kind rawName
             in Doc.stack
                  [ Doc.fillSep
                      [ "You",
                        "are",
                        "trying",
                        "to",
                        "expose",
                        a,
                        thing,
                        "named",
                        name,
                        "but",
                        "I",
                        "cannot",
                        "find",
                        "its",
                        "definition."
                      ],
                    case fmap Doc.fromChars suggestions of
                      [] ->
                        Doc.reflow "I do not see any super similar names in this file. Is the definition missing?"
                      [alt] ->
                        Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
                      alts ->
                        Doc.stack
                          [ "These names seem close though:",
                            Doc.indent 4 . Doc.vcat $ fmap Doc.dullyellow alts
                          ]
                  ]
    ExportOpenAlias region name ->
      Report.Report "BAD EXPORT" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow ("The (..) syntax is for exposing variants of a custom type. It cannot be used with a type alias like `" <> (Name.toChars name <> "` though.")),
            Doc.reflow "Remove the (..) and you should be fine!"
          )
    ImportCtorByName region ctor tipe ->
      Report.Report "BAD IMPORT" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow $
              "You are trying to import the `" <> Name.toChars ctor
                <> "` variant by name:",
            Doc.fillSep
              [ "Try",
                "importing",
                Doc.green (Doc.fromName tipe <> "(..)"),
                "instead.",
                "The",
                "dots",
                "mean",
                "“expose",
                "the",
                Doc.fromName tipe,
                "type",
                "and",
                "all",
                "its",
                "variants",
                "so",
                "it",
                "gives",
                "you",
                "access",
                "to",
                Doc.fromName ctor <> "."
              ]
          )
    ImportNotFound region name _ ->
      --
      -- NOTE: this should always be detected by `builder`
      -- So this error should never actually get printed out.
      --
      Report.Report "UNKNOWN IMPORT" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow $
              "I could not find a `" <> Name.toChars name <> "` module to import!",
            mempty
          )
    ImportOpenAlias region name ->
      Report.Report "BAD IMPORT" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow $
              "The `" <> Name.toChars name <> "` type alias cannot be followed by (..) like this:",
            Doc.reflow "Remove the (..) and it should work."
          )
    ImportExposingNotFound region (ModuleName.Canonical _ home) value possibleNames ->
      let suggestions =
            (fmap Name.toChars . take 4 $ Suggest.sort (Name.toChars home) Name.toChars possibleNames)
       in Report.Report "BAD IMPORT" region suggestions $
            Code.toSnippet
              source
              region
              Nothing
              ( Doc.reflow $
                  "The `" <> Name.toChars home
                    <> "` module does not expose `"
                    <> Name.toChars value
                    <> "`:",
                case fmap Doc.fromChars suggestions of
                  [] ->
                    "I cannot find any super similar exposed names. Maybe it is private?"
                  [alt] ->
                    Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
                  alts ->
                    Doc.stack
                      [ "These names seem close though:",
                        Doc.indent 4 . Doc.vcat $ fmap Doc.dullyellow alts
                      ]
              )
    NotFoundVar region prefix name possibleNames ->
      notFound source region prefix name "variable" possibleNames
    NotFoundType region prefix name possibleNames ->
      notFound source region prefix name "type" possibleNames
    NotFoundVariant region prefix name possibleNames ->
      notFound source region prefix name "variant" possibleNames
    NotFoundBinop region op locals ->
      if op == "==="
        then
          Report.Report "UNKNOWN OPERATOR" region ["=="] $
            Code.toSnippet
              source
              region
              Nothing
              ( "Canopy does not have a (===) operator like JavaScript.",
                "Switch to (==) instead."
              )
        else
          if op == "!=" || op == "!=="
            then
              Report.Report "UNKNOWN OPERATOR" region ["/="] $
                Code.toSnippet
                  source
                  region
                  Nothing
                  ( Doc.reflow "Canopy uses a different name for the “not equal” operator:",
                    Doc.stack
                      [ Doc.reflow "Switch to (/=) instead.",
                        Doc.toSimpleNote ("Our (/=) operator is supposed to look like a real “not equal” sign (≠). I hope that history will remember (" <> (Name.toChars op <> ") as a weird and temporary choice."))
                      ]
                  )
            else
              if op == "**"
                then
                  Report.Report "UNKNOWN OPERATOR" region ["^", "*"] $
                    Code.toSnippet
                      source
                      region
                      Nothing
                      ( Doc.reflow "I do not recognize the (**) operator:",
                        Doc.reflow "Switch to (^) for exponentiation. Or switch to (*) for multiplication."
                      )
                else
                  if op == "%"
                    then
                      Report.Report "UNKNOWN OPERATOR" region [] $
                        Code.toSnippet
                          source
                          region
                          Nothing
                          ( Doc.reflow "Canopy does not use (%) as the remainder operator:",
                            Doc.stack
                              [ Doc.reflow
                                  "If you want the behavior of (%) like in JavaScript, switch to:\
                                  \ <https://package.canopy-lang.org/packages/canopy/core/latest/Basics#remainderBy>",
                                Doc.reflow
                                  "If you want modular arithmetic like in math, switch to:\
                                  \ <https://package.canopy-lang.org/packages/canopy/core/latest/Basics#modBy>",
                                Doc.reflow "The difference is how things work when negative numbers are involved."
                              ]
                          )
                    else
                      let suggestions =
                            (fmap Name.toChars . take 2 $ Suggest.sort (Name.toChars op) Name.toChars (Set.toList locals))

                          format altOp =
                            Doc.green $ "(" <> altOp <> ")"
                       in Report.Report "UNKNOWN OPERATOR" region suggestions $
                            Code.toSnippet
                              source
                              region
                              Nothing
                              ( Doc.reflow ("I do not recognize the (" <> (Name.toChars op <> ") operator.")),
                                Doc.fillSep
                                  ( ["Is", "there", "an", "`import`", "and", "`exposing`", "entry", "for", "it?"]
                                      <> ( case fmap Doc.fromChars suggestions of
                                             [] ->
                                               []
                                             alts ->
                                               ["Maybe", "you", "want"] <> (Doc.commaSep "or" format alts <> ["instead?"])
                                         )
                                  )
                              )
    PatternHasRecordCtor region name ->
      Report.Report "BAD PATTERN" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow $
              "You can construct records by using `" <> Name.toChars name
                <> "` as a function, but it is not available in pattern matching like this:",
            Doc.reflow "I recommend matching the record as a variable and unpacking it later."
          )
    PortPayloadInvalid region portName _badType invalidPayload ->
      let formatDetails (aBadKindOfThing, elaboration) =
            Report.Report "PORT ERROR" region [] $
              Code.toSnippet
                source
                region
                Nothing
                ( Doc.reflow $
                    "The `" <> Name.toChars portName <> "` port is trying to transmit " <> aBadKindOfThing <> ":",
                  Doc.stack
                    [ elaboration,
                      Doc.link
                        "Hint"
                        "Ports are not a traditional FFI, so if you have tons of annoying ports, definitely read"
                        "ports"
                        "to learn how they are meant to work. They require a different mindset!"
                    ]
                )
       in formatDetails $
            case invalidPayload of
              ExtendedRecord ->
                ( "an extended record",
                  Doc.reflow "But the exact shape of the record must be known at compile time. No type variables!"
                )
              Function ->
                ( "a function",
                  Doc.reflow
                    "But functions cannot be sent in and out ports. If we allowed functions in from JS\
                    \ they may perform some side-effects. If we let functions out, they could produce\
                    \ incorrect results because Canopy optimizations assume there are no side-effects."
                )
              TypeVariable name ->
                ( "an unspecified type",
                  Doc.reflow $
                    "But type variables like `" <> Name.toChars name
                      <> "` cannot flow through ports.\
                         \ I need to know exactly what type of data I am getting, so I can guarantee that\
                         \ unexpected data cannot sneak in and crash the Canopy program."
                )
              UnsupportedType name ->
                ( "a `" <> Name.toChars name <> "` value",
                  Doc.stack
                    [ Doc.reflow "I cannot handle that. The types that CAN flow in and out of Canopy include:",
                      Doc.indent 4 . Doc.reflow $
                        "Ints, Floats, Bools, Strings, Maybes, Lists, Arrays,\
                        \ tuples, records, and JSON values.",
                      Doc.reflow
                        "Since JSON values can flow through, you can use JSON encoders and decoders\
                        \ to allow other types through as well. More advanced users often just do\
                        \ everything with encoders and decoders for more control and better errors."
                    ]
                )
    PortTypeInvalid region name portProblem ->
      let formatDetails (before, after) =
            ( Report.Report "BAD PORT" region [] . Code.toSnippet source region Nothing $
                ( Doc.reflow before,
                  Doc.stack
                    [ after,
                      Doc.link
                        "Hint"
                        "Read"
                        "ports"
                        "for more advice. For example, do not end up with one port per JS function!"
                    ]
                )
            )
       in formatDetails $
            case portProblem of
              CmdNoArg ->
                ( "The `" <> Name.toChars name <> "` port cannot be just a command.",
                  Doc.reflow
                    "It can be (() -> Cmd msg) if you just need to trigger a JavaScript\
                    \ function, but there is often a better way to set things up."
                )
              CmdExtraArgs n ->
                ( "The `" <> Name.toChars name <> "` port can only send ONE value out to JavaScript.",
                  let theseItemsInSomething
                        | n == 2 = "both of these items into a tuple or record"
                        | n == 3 = ("these " <> (show n <> " items into a tuple or record"))
                        | otherwise = ("these " <> (show n <> " items into a record"))
                   in Doc.reflow ("You can put " <> (theseItemsInSomething <> " to send them out though."))
                )
              CmdBadMsg ->
                ( "The `" <> Name.toChars name <> "` port cannot send any messages to the `update` function.",
                  Doc.reflow
                    "It must produce a (Cmd msg) type. Notice the lower case `msg` type\
                    \ variable. The command will trigger some JS code, but it will not send\
                    \ anything particular back to Canopy."
                )
              SubBad ->
                ( "There is something off about this `" <> Name.toChars name <> "` port declaration.",
                  Doc.stack
                    [ Doc.reflow "To receive messages from JavaScript, you need to define a port like this:",
                      (Doc.indent 4 . Doc.dullyellow) . Doc.fromChars $ ("port " <> Name.toChars name <> " : (Int -> msg) -> Sub msg"),
                      Doc.reflow
                        "Now every time JS sends an `Int` to this port, it is converted to a `msg`.\
                        \ And if you subscribe, those `msg` values will be piped into your `update`\
                        \ function. The only thing you can customize here is the `Int` type."
                    ]
                )
              NotCmdOrSub ->
                ( "I am confused about the `" <> Name.toChars name <> "` port declaration.",
                  Doc.reflow
                    "Ports need to produce a command (Cmd) or a subscription (Sub) but\
                    \ this is neither. I do not know how to handle this."
                )
    RecursiveAlias region name args tipe others ->
      aliasRecursionReport source region name args tipe others
    RecursiveDecl region name names ->
      let makeTheory question details =
            Doc.fillSep (fmap (Doc.dullyellow . Doc.fromChars) (words question) <> fmap Doc.fromChars (words details))
       in ( Report.Report "CYCLIC DEFINITION" region [] . Code.toSnippet source region Nothing $
              ( case names of
                  [] ->
                    ( Doc.reflow $
                        "The `" <> Name.toChars name <> "` value is defined directly in terms of itself, causing an infinite loop.",
                      Doc.stack
                        [ makeTheory "Are you trying to mutate a variable?" ("Canopy does not have mutation, so when I see " <> (Name.toChars name <> (" defined in terms of " <> (Name.toChars name <> ", I treat it as a recursive definition. Try giving the new value a new name!")))),
                          makeTheory "Maybe you DO want a recursive value?" ("To define " <> (Name.toChars name <> (" we need to know what " <> (Name.toChars name <> (" is, so let’s expand it. Wait, but now we need to know what " <> (Name.toChars name <> " is, so let’s expand it... This will keep going infinitely!")))))),
                          Doc.link
                            "Hint"
                            "The root problem is often a typo in some variable name, but I recommend reading"
                            "bad-recursion"
                            "for more detailed advice, especially if you actually do need a recursive value."
                        ]
                    )
                  _ : _ ->
                    ( Doc.reflow $
                        "The `" <> Name.toChars name <> "` definition is causing a very tricky infinite loop.",
                      Doc.stack
                        [ Doc.reflow $
                            "The `" <> Name.toChars name
                              <> "` value depends on itself through the following chain of definitions:",
                          Doc.cycle 4 name names,
                          Doc.link
                            "Hint"
                            "The root problem is often a typo in some variable name, but I recommend reading"
                            "bad-recursion"
                            "for more detailed advice, especially if you actually do want mutually recursive values."
                        ]
                    )
              )
          )
    RecursiveLet (Ann.At region name) names ->
      Report.Report "CYCLIC VALUE" region [] . Code.toSnippet source region Nothing $
        ( case names of
            [] ->
              let makeTheory question details =
                    Doc.fillSep (fmap (Doc.dullyellow . Doc.fromChars) (words question) <> fmap Doc.fromChars (words details))
               in ( Doc.reflow $
                      "The `" <> Name.toChars name <> "` value is defined directly in terms of itself, causing an infinite loop.",
                    Doc.stack
                      [ makeTheory "Are you trying to mutate a variable?" ("Canopy does not have mutation, so when I see " <> (Name.toChars name <> (" defined in terms of " <> (Name.toChars name <> ", I treat it as a recursive definition. Try giving the new value a new name!")))),
                        makeTheory "Maybe you DO want a recursive value?" ("To define " <> (Name.toChars name <> (" we need to know what " <> (Name.toChars name <> (" is, so let’s expand it. Wait, but now we need to know what " <> (Name.toChars name <> " is, so let’s expand it... This will keep going infinitely!")))))),
                        Doc.link
                          "Hint"
                          "The root problem is often a typo in some variable name, but I recommend reading"
                          "bad-recursion"
                          "for more detailed advice, especially if you actually do need a recursive value."
                      ]
                  )
            _ ->
              ( Doc.reflow "I do not allow cyclic values in `let` expressions.",
                Doc.stack
                  [ Doc.reflow $
                      "The `" <> Name.toChars name
                        <> "` value depends on itself through the following chain of definitions:",
                    Doc.cycle 4 name names,
                    Doc.link
                      "Hint"
                      "The root problem is often a typo in some variable name, but I recommend reading"
                      "bad-recursion"
                      "for more detailed advice, especially if you actually do want mutually recursive values."
                  ]
              )
        )
    Shadowing name r1 r2 ->
      Report.Report "SHADOWING" r2 [] $
        Code.toPair
          source
          r1
          r2
          ( "These variables cannot have the same name:",
            advice
          )
          ( Doc.reflow $ "The name `" <> Name.toChars name <> "` is first defined here:",
            "But then it is defined AGAIN over here:",
            advice
          )
      where
        advice =
          Doc.stack
            [ Doc.reflow "Think of a more helpful name for one of them and you should be all set!",
              Doc.link
                "Note"
                "Linters advise against shadowing, so Canopy makes “best practices” the default. Read"
                "shadowing"
                "for more details on this choice."
            ]
    TupleLargerThanThree region ->
      Report.Report "BAD TUPLE" region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( "I only accept tuples with two or three items. This has too many:",
            Doc.stack
              [ Doc.reflow
                  "I recommend switching to records. Each item will be named, and you can use\
                  \ the `point.x` syntax to access them.",
                Doc.link
                  "Note"
                  "Read"
                  "tuples"
                  "for more comprehensive advice on working with large chunks of data in Canopy."
              ]
          )
    TypeVarsUnboundInUnion unionRegion typeName allVars unbound unbounds ->
      unboundTypeVars source unionRegion ["type"] typeName allVars unbound unbounds
    TypeVarsMessedUpInAlias aliasRegion typeName allVars unusedVars unboundVars ->
      case (unusedVars, unboundVars) of
        (unused : unuseds, []) ->
          let backQuote name =
                "`" <> Doc.fromName name <> "`"

              allUnusedNames =
                fmap fst unusedVars

              (title, subRegion, overview, stuff) =
                case unuseds of
                  [] ->
                    ( "UNUSED TYPE VARIABLE",
                      Just (snd unused),
                      [ "Type",
                        "alias",
                        backQuote typeName,
                        "does",
                        "not",
                        "use",
                        "the",
                        backQuote (fst unused),
                        "type",
                        "variable."
                      ],
                      [Doc.dullyellow (backQuote (fst unused))]
                    )
                  _ : _ ->
                    ( "UNUSED TYPE VARIABLES",
                      Nothing,
                      ["Type", "variables"] <> (Doc.commaSep "and" id (fmap Doc.fromName allUnusedNames) <> ["are", "unused", "in", "the", backQuote typeName, "definition."]),
                      Doc.commaSep "and" Doc.dullyellow (fmap Doc.fromName allUnusedNames)
                    )
           in Report.Report title aliasRegion [] $
                Code.toSnippet
                  source
                  aliasRegion
                  subRegion
                  ( Doc.fillSep overview,
                    Doc.stack
                      [ Doc.fillSep (["I", "recommend", "removing"] <> (stuff <> ["from", "the", "declaration,", "like", "this:"])),
                        Doc.indent 4 . Doc.hsep $ (["type", "alias", Doc.green (Doc.fromName typeName)] <> (fmap Doc.fromName (filter (`notElem` allUnusedNames) allVars) <> ["=", "..."])),
                        Doc.reflow
                          "Why? Well, if I allowed `type alias Height a = Float` I would need to answer\
                          \ some weird questions. Is `Height Bool` the same as `Float`? Is `Height Bool`\
                          \ the same as `Height Int`? My solution is to not need to ask them!"
                      ]
                  )
        ([], unbound : unbounds) ->
          unboundTypeVars source aliasRegion ["type", "alias"] typeName allVars unbound unbounds
        (_, _) ->
          let unused = fmap fst unusedVars
              unbound = fmap fst unboundVars

              theseAreUsed =
                case unbound of
                  [x] ->
                    [ "Type",
                      "variable",
                      Doc.dullyellow ("`" <> Doc.fromName x <> "`"),
                      "appears",
                      "in",
                      "the",
                      "definition,",
                      "but",
                      "I",
                      "do",
                      "not",
                      "see",
                      "it",
                      "declared."
                    ]
                  _ ->
                    ["Type", "variables"] <> (Doc.commaSep "and" Doc.dullyellow (fmap Doc.fromName unbound) <> ["are", "used", "in", "the", "definition,", "but", "I", "do", "not", "see", "them", "declared."])

              butTheseAreUnused =
                case unused of
                  [x] ->
                    [ "Likewise,",
                      "type",
                      "variable",
                      Doc.dullyellow ("`" <> Doc.fromName x <> "`"),
                      "is",
                      "delared,",
                      "but",
                      "not",
                      "used."
                    ]
                  _ ->
                    ["Likewise,", "type", "variables"] <> (Doc.commaSep "and" Doc.dullyellow (fmap Doc.fromName unused) <> ["are", "delared,", "but", "not", "used."])
           in Report.Report "TYPE VARIABLE PROBLEMS" aliasRegion [] $
                Code.toSnippet
                  source
                  aliasRegion
                  Nothing
                  ( Doc.reflow $
                      "Type alias `" <> Name.toChars typeName <> "` has some type variable problems.",
                    Doc.stack
                      [ Doc.fillSep (theseAreUsed <> butTheseAreUnused),
                        Doc.reflow "My guess is that a definition like this will work better:",
                        Doc.indent 4 . Doc.hsep $ (["type", "alias", Doc.fromName typeName] <> (fmap Doc.fromName (filter (`notElem` unused) allVars) <> (fmap (Doc.green . Doc.fromName) unbound <> ["=", "..."])))
                      ]
                  )
    FFIFileNotFound region filePath ->
      Report.Report "FFI FILE NOT FOUND" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("Cannot find FFI file: " <> filePath)
          , Doc.reflow "Make sure the file exists and the path is correct."
          )
    FFIFileTimeout region filePath timeout ->
      Report.Report "FFI FILE TIMEOUT" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("Timeout reading FFI file: " <> filePath <> " after " <> show timeout <> "ms")
          , Doc.reflow "The file may be too large or there may be a filesystem issue."
          )
    FFIParseError region filePath parseErr ->
      Report.Report "FFI PARSE ERROR" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("Error parsing FFI file: " <> filePath)
          , Doc.reflow ("Parse error: " <> parseErr)
          )
    FFIPathTraversal region filePath reason ->
      Report.Report "FFI PATH ERROR" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("The foreign import path is not allowed: " <> filePath)
          , Doc.stack
              [ Doc.reflow reason
              , Doc.reflow "FFI source paths must be relative paths within your project directory, ending in .js or .mjs, without '..' components."
              ]
          )
    FFIInvalidType region filePath typeName typeErr ->
      Report.Report "FFI INVALID TYPE" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("Invalid type in FFI file: " <> filePath)
          , Doc.reflow ("Type " <> Name.toChars typeName <> ": " <> typeErr)
          )
    FFIMissingAnnotation region filePath funcName ->
      Report.Report "FFI MISSING ANNOTATION" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("Missing type annotation in FFI file: " <> filePath)
          , Doc.reflow ("Function " <> Name.toChars funcName <> " needs a type annotation.")
          )
    FFICircularDependency region filePath deps ->
      Report.Report "FFI CIRCULAR DEPENDENCY" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("Circular dependency detected in FFI file: " <> filePath)
          , Doc.reflow ("Dependency chain: " <> show deps)
          )
    FFITypeNotFound region filePath typeName typeErr suggestions ->
      let nearbyNames =
            fmap Name.toChars (take 4 (Suggest.sort (Name.toChars typeName) Name.toChars suggestions))
       in Report.Report "FFI TYPE NOT FOUND" region nearbyNames $
            Code.toSnippet source region Nothing
              ( Doc.reflow ("Unknown type in FFI file: " <> filePath)
              , Doc.stack
                  [ Doc.reflow ("The type `" <> Name.toChars typeName <> "` is not in scope: " <> typeErr)
                  , case fmap Doc.fromChars nearbyNames of
                      [] -> Doc.reflow "Make sure this type is imported or defined in your module."
                      [alt] -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
                      alts -> Doc.stack ["These types seem close though:", Doc.indent 4 (Doc.vcat (fmap Doc.dullyellow alts))]
                  ]
              )
    LazyImportNotFound region name suggestions ->
      let nearbyNames =
            fmap Name.toChars (take 4 (Suggest.sort (Name.toChars name) Name.toChars suggestions))
       in Report.Report "LAZY IMPORT NOT FOUND" region nearbyNames $
            Code.toSnippet source region Nothing
              ( Doc.reflow ("I cannot find a `" <> Name.toChars name <> "` module for this lazy import:")
              , case fmap Doc.fromChars nearbyNames of
                  [] -> Doc.reflow "I cannot find any similar module names. Is the module missing from your dependencies?"
                  [alt] -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
                  alts -> Doc.stack ["These names seem close though:", Doc.indent 4 (Doc.vcat (fmap Doc.dullyellow alts))]
              )
    LazyImportCoreModule region name ->
      Report.Report "BAD LAZY IMPORT" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("The `" <> Name.toChars name <> "` module is a core library module:")
          , Doc.reflow "Core modules like Basics, List, Maybe, Result, String, and Platform are always loaded eagerly. They cannot be lazy-imported because they are required for every Canopy program."
          )
    LazyImportInPackage region name ->
      Report.Report "BAD LAZY IMPORT" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("You are using `lazy import " <> Name.toChars name <> "` inside a package:")
          , Doc.reflow "Lazy imports enable code splitting, which only works in applications. Packages must use regular imports so their code can be bundled by the application that depends on them."
          )
    LazyImportSelf region name ->
      Report.Report "BAD LAZY IMPORT" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("The module `" <> Name.toChars name <> "` is trying to lazy-import itself:")
          , Doc.reflow "A module cannot lazily load itself. Remove the `lazy` keyword from this import."
          )
    LazyImportKernel region name ->
      Report.Report "BAD LAZY IMPORT" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow ("The `" <> Name.toChars name <> "` module is an internal kernel module:")
          , Doc.reflow "Kernel modules are internal to the compiler runtime and cannot be lazy-imported. They are always loaded eagerly as part of the runtime system."
          )

-- TO DIAGNOSTIC

-- | Convert a canonicalization error to a structured 'Diagnostic'.
--
-- Error code mapping (E03xx range):
--
-- @
-- AnnotationTooShort       -> E0300
-- AmbiguousVar             -> E0301
-- AmbiguousType            -> E0302
-- AmbiguousVariant         -> E0303
-- AmbiguousBinop           -> E0304
-- BadArity                 -> E0305
-- Binop                    -> E0306
-- DuplicateDecl            -> E0307
-- DuplicateType            -> E0308
-- DuplicateCtor            -> E0309
-- DuplicateBinop           -> E0310
-- DuplicateField           -> E0311
-- DuplicateAliasArg        -> E0312
-- DuplicateUnionArg        -> E0313
-- DuplicatePattern         -> E0314
-- EffectNotFound           -> E0315
-- EffectFunctionNotFound   -> E0316
-- ExportDuplicate          -> E0317
-- ExportNotFound           -> E0318
-- ExportOpenAlias          -> E0319
-- ImportCtorByName         -> E0320
-- ImportNotFound           -> E0321
-- ImportOpenAlias          -> E0322
-- ImportExposingNotFound   -> E0323
-- NotFoundVar              -> E0324
-- NotFoundType             -> E0325
-- NotFoundVariant          -> E0326
-- NotFoundBinop            -> E0327
-- PatternHasRecordCtor     -> E0328
-- PortPayloadInvalid       -> E0329
-- PortTypeInvalid          -> E0330
-- RecursiveAlias           -> E0331
-- RecursiveDecl            -> E0332
-- RecursiveLet             -> E0333
-- Shadowing                -> E0334
-- TupleLargerThanThree     -> E0335
-- TypeVarsUnboundInUnion   -> E0336
-- TypeVarsMessedUpInAlias  -> E0337
-- FFIFileNotFound          -> E0338
-- FFIFileTimeout           -> E0339
-- FFIParseError            -> E0340
-- FFIPathTraversal         -> E0349
-- FFIInvalidType           -> E0341
-- FFIMissingAnnotation     -> E0342
-- FFICircularDependency    -> E0343
-- FFITypeNotFound          -> E0344
-- LazyImportNotFound       -> E0345
-- LazyImportCoreModule     -> E0346
-- LazyImportInPackage      -> E0347
-- LazyImportSelf           -> E0347
-- LazyImportKernel         -> E0348
-- @
toDiagnostic :: Code.Source -> Error -> Diagnostic
toDiagnostic source err =
  case err of
    AnnotationTooShort region name index leftovers ->
      annotationTooShortDiagnostic source region name index leftovers
    AmbiguousVar region maybePrefix name h hs ->
      ambiguousNameDiagnostic source region maybePrefix name h hs "variable" (EC.canonError 1)
    AmbiguousType region maybePrefix name h hs ->
      ambiguousNameDiagnostic source region maybePrefix name h hs "type" (EC.canonError 2)
    AmbiguousVariant region maybePrefix name h hs ->
      ambiguousNameDiagnostic source region maybePrefix name h hs "variant" (EC.canonError 3)
    AmbiguousBinop region name h hs ->
      ambiguousNameDiagnostic source region Nothing name h hs "operator" (EC.canonError 4)
    BadArity region badArityContext name expected actual ->
      badArityDiagnostic source region badArityContext name expected actual
    Binop region op1 op2 ->
      binopDiagnostic source region op1 op2
    DuplicateDecl name r1 r2 ->
      nameClashDiagnostic source r1 r2 (EC.canonError 7) ("This file has multiple `" <> Name.toChars name <> "` declarations.")
    DuplicateType name r1 r2 ->
      nameClashDiagnostic source r1 r2 (EC.canonError 8) ("This file defines multiple `" <> Name.toChars name <> "` types.")
    DuplicateCtor name r1 r2 ->
      nameClashDiagnostic source r1 r2 (EC.canonError 9) ("This file defines multiple `" <> Name.toChars name <> "` type constructors.")
    DuplicateBinop name r1 r2 ->
      nameClashDiagnostic source r1 r2 (EC.canonError 10) ("This file defines multiple (" <> Name.toChars name <> ") operators.")
    DuplicateField name r1 r2 ->
      nameClashDiagnostic source r1 r2 (EC.canonError 11) ("This record has multiple `" <> Name.toChars name <> "` fields.")
    DuplicateAliasArg typeName name r1 r2 ->
      nameClashDiagnostic source r1 r2 (EC.canonError 12) ("The `" <> Name.toChars typeName <> "` type alias has multiple `" <> Name.toChars name <> "` type variables.")
    DuplicateUnionArg typeName name r1 r2 ->
      nameClashDiagnostic source r1 r2 (EC.canonError 13) ("The `" <> Name.toChars typeName <> "` type has multiple `" <> Name.toChars name <> "` type variables.")
    DuplicatePattern context name r1 r2 ->
      nameClashDiagnostic source r1 r2 (EC.canonError 14) (duplicatePatternMessage context name)
    EffectNotFound region name ->
      effectNotFoundDiagnostic source region name
    EffectFunctionNotFound region name ->
      effectFunctionNotFoundDiagnostic source region name
    ExportDuplicate name r1 r2 ->
      exportDuplicateDiagnostic source name r1 r2
    ExportNotFound region kind rawName possibleNames ->
      exportNotFoundDiagnostic source region kind rawName possibleNames
    ExportOpenAlias region name ->
      exportOpenAliasDiagnostic source region name
    ImportCtorByName region ctor tipe ->
      importCtorByNameDiagnostic source region ctor tipe
    ImportNotFound region name _ ->
      importNotFoundDiagnostic source region name
    ImportOpenAlias region name ->
      importOpenAliasDiagnostic source region name
    ImportExposingNotFound region home value possibleNames ->
      importExposingNotFoundDiagnostic source region home value possibleNames
    NotFoundVar region prefix name possibleNames ->
      notFoundDiagnostic source region prefix name "variable" possibleNames (EC.canonError 24)
    NotFoundType region prefix name possibleNames ->
      notFoundDiagnostic source region prefix name "type" possibleNames (EC.canonError 25)
    NotFoundVariant region prefix name possibleNames ->
      notFoundDiagnostic source region prefix name "variant" possibleNames (EC.canonError 26)
    NotFoundBinop region op locals ->
      notFoundBinopDiagnostic source region op locals
    PatternHasRecordCtor region name ->
      patternHasRecordCtorDiagnostic source region name
    PortPayloadInvalid region portName _badType invalidPayload ->
      portPayloadInvalidDiagnostic source region portName invalidPayload
    PortTypeInvalid region name portProblem ->
      portTypeInvalidDiagnostic source region name portProblem
    RecursiveAlias region name args tipe others ->
      recursiveAliasDiagnostic source region name args tipe others
    RecursiveDecl region name names ->
      recursiveDeclDiagnostic source region name names
    RecursiveLet (Ann.At region name) names ->
      recursiveLetDiagnostic source region name names
    Shadowing name r1 r2 ->
      shadowingDiagnostic source name r1 r2
    TupleLargerThanThree region ->
      tupleLargerThanThreeDiagnostic source region
    TypeVarsUnboundInUnion unionRegion typeName allVars unbound unbounds ->
      typeVarsUnboundInUnionDiagnostic source unionRegion typeName allVars unbound unbounds
    TypeVarsMessedUpInAlias aliasRegion typeName allVars unusedVars unboundVars ->
      typeVarsMessedUpInAliasDiagnostic source aliasRegion typeName allVars unusedVars unboundVars
    FFIFileNotFound region filePath ->
      ffiFileNotFoundDiagnostic source region filePath
    FFIFileTimeout region filePath timeout ->
      ffiFileTimeoutDiagnostic source region filePath timeout
    FFIParseError region filePath parseErr ->
      ffiParseErrorDiagnostic source region filePath parseErr
    FFIPathTraversal region filePath reason ->
      ffiPathTraversalDiagnostic source region filePath reason
    FFIInvalidType region filePath typeName typeErr ->
      ffiInvalidTypeDiagnostic source region filePath typeName typeErr
    FFIMissingAnnotation region filePath funcName ->
      ffiMissingAnnotationDiagnostic source region filePath funcName
    FFICircularDependency region filePath deps ->
      ffiCircularDependencyDiagnostic source region filePath deps
    FFITypeNotFound region filePath typeName typeErr suggestions ->
      ffiTypeNotFoundDiagnostic source region filePath typeName typeErr suggestions
    LazyImportNotFound region name suggestions ->
      lazyImportNotFoundDiagnostic source region name suggestions
    LazyImportCoreModule region name ->
      lazyImportCoreModuleDiagnostic source region name
    LazyImportInPackage region name ->
      lazyImportInPackageDiagnostic source region name
    LazyImportSelf region name ->
      lazyImportSelfDiagnostic source region name
    LazyImportKernel region name ->
      lazyImportKernelDiagnostic source region name

-- | Extract the message 'Doc.Doc' from a 'Report.Report'.
--
-- Allows diagnostic helpers to reuse the message-building logic already
-- present in 'toReport' without duplicating complex Doc construction.
extractReportMessage :: Report.Report -> Doc.Doc
extractReportMessage (Report.Report _ _ _ msg) = msg

-- | Build a diagnostic for a type annotation argument count mismatch.
annotationTooShortDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Index.ZeroBased -> Int -> Diagnostic
annotationTooShortDiagnostic source region name index leftovers =
  Diag.makeDiagnostic
    (EC.canonError 0)
    Diag.SError
    Diag.PhaseCanon
    "BAD TYPE ANNOTATION"
    (Text.pack ("Type annotation for `" <> Name.toChars name <> "` has too few arguments"))
    (LabeledSpan region "annotation argument count mismatch" SpanPrimary)
    (Code.toSnippet source region Nothing (annotationTooShortMessage name numTypeArgs numDefArgs, annotationTooShortHint leftovers))
  where
    numTypeArgs = Index.toMachine index
    numDefArgs = numTypeArgs + leftovers

-- | Format the primary message for an annotation-too-short error.
annotationTooShortMessage :: Name.Name -> Int -> Int -> Doc.Doc
annotationTooShortMessage name numTypeArgs numDefArgs =
  Doc.reflow ("The type annotation for `" <> Name.toChars name <> "` says it can accept " <> Doc.args numTypeArgs <> ", but the definition says it has " <> Doc.args numDefArgs <> ":")

-- | Format the hint for an annotation-too-short error.
annotationTooShortHint :: Int -> Doc.Doc
annotationTooShortHint leftovers =
  Doc.reflow ("Is the type annotation missing something? Should some argument" <> (if leftovers == 1 then "" else "s") <> " be deleted? Maybe some parentheses are missing?")

-- | Build a diagnostic for an ambiguous name (variable, type, variant, or operator).
--
-- Delegates the complex message Doc to the existing 'ambiguousName' helper.
ambiguousNameDiagnostic :: Code.Source -> Ann.Region -> Maybe Name.Name -> Name.Name -> ModuleName.Canonical -> OneOrMore.OneOrMore ModuleName.Canonical -> String -> Diag.ErrorCode -> Diagnostic
ambiguousNameDiagnostic source region maybePrefix name h hs thing code =
  Diag.makeDiagnostic
    code
    Diag.SError
    Diag.PhaseCanon
    "AMBIGUOUS NAME"
    (Text.pack ("Ambiguous " <> thing <> " `" <> Name.toChars name <> "`"))
    (LabeledSpan region (Text.pack ("ambiguous " <> thing)) SpanPrimary)
    (extractReportMessage (ambiguousName source region maybePrefix name h hs thing))

-- | Build a diagnostic for an arity mismatch (too few or too many arguments).
badArityDiagnostic :: Code.Source -> Ann.Region -> BadArityContext -> Name.Name -> Int -> Int -> Diagnostic
badArityDiagnostic source region badArityContext name expected actual =
  Diag.makeDiagnostic
    (EC.canonError 5)
    Diag.SError
    Diag.PhaseCanon
    (if actual < expected then "TOO FEW ARGS" else "TOO MANY ARGS")
    (Text.pack (badArityContextThing badArityContext <> " `" <> Name.toChars name <> "` given wrong number of arguments"))
    (LabeledSpan region "wrong number of arguments" SpanPrimary)
    (badArityMessage source region badArityContext name expected actual)

-- | Produce the kind label for a 'BadArityContext'.
badArityContextThing :: BadArityContext -> String
badArityContextThing badArityContext =
  case badArityContext of
    TypeArity -> "Type"
    PatternArity -> "Variant"

-- | Build the message Doc for a bad-arity error.
badArityMessage :: Code.Source -> Ann.Region -> BadArityContext -> Name.Name -> Int -> Int -> Doc.Doc
badArityMessage source region badArityContext name expected actual =
  let thing = case badArityContext of
                TypeArity -> "type"
                PatternArity -> "variant"
      base = Doc.reflow ("The `" <> Name.toChars name <> "` " <> thing <> " needs " <> Doc.args expected <> ", but I see " <> show actual <> " instead:")
  in if actual < expected
    then Code.toSnippet source region Nothing (base, Doc.reflow "What is missing? Are some parentheses misplaced?")
    else Code.toSnippet source region Nothing (base, if actual - expected == 1 then "Which is the extra one? Maybe some parentheses are missing?" else "Which are the extra ones? Maybe some parentheses are missing?")

-- | Build a diagnostic for mixed infix operators without parentheses.
binopDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Name.Name -> Diagnostic
binopDiagnostic source region op1 op2 =
  Diag.makeDiagnostic
    (EC.canonError 6)
    Diag.SError
    Diag.PhaseCanon
    "INFIX PROBLEM"
    (Text.pack ("Cannot mix (" <> Name.toChars op1 <> ") and (" <> Name.toChars op2 <> ") without parentheses"))
    (LabeledSpan region "mixed operators" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("You cannot mix (" <> Name.toChars op1 <> ") and (" <> Name.toChars op2 <> ") without parentheses."), Doc.reflow "I do not know how to group these expressions. Add parentheses for me!"))

-- | Build a diagnostic for a name clash (duplicate declaration, type, ctor, etc.).
--
-- Delegates the message Doc to the existing 'nameClash' helper.
nameClashDiagnostic :: Code.Source -> Ann.Region -> Ann.Region -> Diag.ErrorCode -> String -> Diagnostic
nameClashDiagnostic source r1 r2 code message =
  Diag.makeDiagnostic
    code
    Diag.SError
    Diag.PhaseCanon
    "NAME CLASH"
    (Text.pack message)
    (LabeledSpan r2 "duplicate definition" SpanPrimary)
    (extractReportMessage (nameClash source r1 r2 message))

-- | Produce the clash message for a duplicate pattern variable.
duplicatePatternMessage :: DuplicatePatternContext -> Name.Name -> String
duplicatePatternMessage context name =
  case context of
    DPLambdaArgs -> "This anonymous function has multiple `" <> Name.toChars name <> "` arguments."
    DPFuncArgs funcName -> "The `" <> Name.toChars funcName <> "` function has multiple `" <> Name.toChars name <> "` arguments."
    DPCaseBranch -> "This `case` pattern has multiple `" <> Name.toChars name <> "` variables."
    DPLetBinding -> "This `let` expression defines `" <> Name.toChars name <> "` more than once!"
    DPDestruct -> "This pattern contains multiple `" <> Name.toChars name <> "` variables."

-- | Build a diagnostic for a missing effect type declaration.
effectNotFoundDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
effectNotFoundDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 15)
    Diag.SError
    Diag.PhaseCanon
    "EFFECT PROBLEM"
    (Text.pack ("Effect type `" <> Name.toChars name <> "` not found in this file"))
    (LabeledSpan region "effect type not found" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("You have declared that `" <> (Name.toChars name <> "` is an effect type:")), Doc.reflow ("But I cannot find a custom type named `" <> (Name.toChars name <> "` in this file!"))))

-- | Build a diagnostic for a missing effect function declaration.
effectFunctionNotFoundDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
effectFunctionNotFoundDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 16)
    Diag.SError
    Diag.PhaseCanon
    "EFFECT PROBLEM"
    (Text.pack ("Effect function `" <> Name.toChars name <> "` not defined in this file"))
    (LabeledSpan region "effect function not found" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("This kind of effect module must define a `" <> (Name.toChars name <> "` function.")), Doc.reflow ("But I cannot find `" <> (Name.toChars name <> "` in this file!"))))

-- | Build a diagnostic for a duplicated export.
exportDuplicateDiagnostic :: Code.Source -> Name.Name -> Ann.Region -> Ann.Region -> Diagnostic
exportDuplicateDiagnostic source name r1 r2 =
  Diag.makeDiagnostic
    (EC.canonError 17)
    Diag.SError
    Diag.PhaseCanon
    "REDUNDANT EXPORT"
    (Text.pack msg)
    (LabeledSpan r2 "duplicate export" SpanPrimary)
    (Code.toPair source r1 r2 (Doc.reflow msg, "Remove one of them and you should be all set!") (Doc.reflow (msg <> " Once here:"), "And again right here:", "Remove one of them and you should be all set!"))
  where
    msg = "You are trying to expose `" <> Name.toChars name <> "` multiple times!"

-- | Build a diagnostic for an export that references an unknown name.
--
-- Delegates the message Doc to 'toReport' to reuse suggestion-formatting logic.
exportNotFoundDiagnostic :: Code.Source -> Ann.Region -> VarKind -> Name.Name -> [Name.Name] -> Diagnostic
exportNotFoundDiagnostic source region kind rawName possibleNames =
  Diag.makeDiagnostic
    (EC.canonError 18)
    Diag.SError
    Diag.PhaseCanon
    "UNKNOWN EXPORT"
    (Text.pack ("Cannot find definition for exported name `" <> Name.toChars rawName <> "`"))
    (LabeledSpan region "unknown export" SpanPrimary)
    (extractReportMessage (toReport source (ExportNotFound region kind rawName possibleNames)))

-- | Build a diagnostic for exposing (..) on a type alias in an export.
exportOpenAliasDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
exportOpenAliasDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 19)
    Diag.SError
    Diag.PhaseCanon
    "BAD EXPORT"
    (Text.pack ("Cannot use (..) with type alias `" <> Name.toChars name <> "`"))
    (LabeledSpan region "open alias in export" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("The (..) syntax is for exposing variants of a custom type. It cannot be used with a type alias like `" <> (Name.toChars name <> "` though.")), Doc.reflow "Remove the (..) and you should be fine!"))

-- | Build a diagnostic for importing a variant constructor by name directly.
importCtorByNameDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Name.Name -> Diagnostic
importCtorByNameDiagnostic source region ctor tipe =
  Diag.makeDiagnostic
    (EC.canonError 20)
    Diag.SError
    Diag.PhaseCanon
    "BAD IMPORT"
    (Text.pack ("Cannot import variant `" <> Name.toChars ctor <> "` by name; import via its type"))
    (LabeledSpan region "variant imported by name" SpanPrimary)
    (extractReportMessage (toReport source (ImportCtorByName region ctor tipe)))

-- | Build a diagnostic for an unknown module import.
importNotFoundDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
importNotFoundDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 21)
    Diag.SError
    Diag.PhaseCanon
    "UNKNOWN IMPORT"
    (Text.pack ("Cannot find module `" <> Name.toChars name <> "`"))
    (LabeledSpan region "module not found" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("I could not find a `" <> Name.toChars name <> "` module to import!"), mempty))

-- | Build a diagnostic for using (..) with a type alias in an import.
importOpenAliasDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
importOpenAliasDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 22)
    Diag.SError
    Diag.PhaseCanon
    "BAD IMPORT"
    (Text.pack ("Cannot use (..) with type alias `" <> Name.toChars name <> "` in import"))
    (LabeledSpan region "open alias in import" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("The `" <> Name.toChars name <> "` type alias cannot be followed by (..) like this:"), Doc.reflow "Remove the (..) and it should work."))

-- | Build a diagnostic for an exposing clause that references an unknown name.
--
-- Delegates the message Doc to 'toReport' to reuse suggestion-formatting logic.
importExposingNotFoundDiagnostic :: Code.Source -> Ann.Region -> ModuleName.Canonical -> Name.Name -> [Name.Name] -> Diagnostic
importExposingNotFoundDiagnostic source region home value possibleNames =
  Diag.makeDiagnostic
    (EC.canonError 23)
    Diag.SError
    Diag.PhaseCanon
    "BAD IMPORT"
    (Text.pack ("Module `" <> Name.toChars homeName <> "` does not expose `" <> Name.toChars value <> "`"))
    (LabeledSpan region "unexposed name" SpanPrimary)
    (extractReportMessage (toReport source (ImportExposingNotFound region home value possibleNames)))
  where
    (ModuleName.Canonical _ homeName) = home

-- | Build a diagnostic for a name that cannot be resolved.
--
-- Delegates the message Doc to the existing 'notFound' helper.
notFoundDiagnostic :: Code.Source -> Ann.Region -> Maybe Name.Name -> Name.Name -> String -> PossibleNames -> Diag.ErrorCode -> Diagnostic
notFoundDiagnostic source region maybePrefix name thing possibleNames code =
  addNameSuggestions region name possibleNames
    ( Diag.makeDiagnostic
        code
        Diag.SError
        Diag.PhaseCanon
        "NAMING ERROR"
        (Text.pack ("Cannot find `" <> givenName <> "` " <> thing))
        (LabeledSpan region (Text.pack (thing <> " not found")) SpanPrimary)
        (extractReportMessage (notFound source region maybePrefix name thing possibleNames))
    )
  where
    givenName = maybe Name.toChars toQualString maybePrefix name

-- | Add structured suggestions from PossibleNames to a diagnostic.
addNameSuggestions :: Ann.Region -> Name.Name -> PossibleNames -> Diagnostic -> Diagnostic
addNameSuggestions region name (PossibleNames locals quals) diag =
  foldr Diag.addSuggestion diag (take 3 (fmap (toNameSuggestion region) sorted))
  where
    allNames = Set.toList locals <> concatMap Set.toList (Map.elems quals)
    sorted = Suggest.sort (Name.toChars name) Name.toChars allNames

-- | Convert a suggested name into a structured Suggestion.
toNameSuggestion :: Ann.Region -> Name.Name -> Suggestion
toNameSuggestion region suggested =
  Suggestion
    region
    (Text.pack (Name.toChars suggested))
    (Text.pack ("Did you mean `" <> Name.toChars suggested <> "`?"))
    Likely

-- | Build a diagnostic for an unknown binary operator.
--
-- Delegates the message Doc to 'toReport' to reuse the operator-specific hints.
notFoundBinopDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Set.Set Name.Name -> Diagnostic
notFoundBinopDiagnostic source region op locals =
  addBinopSuggestions region op locals
    ( Diag.makeDiagnostic
        (EC.canonError 27)
        Diag.SError
        Diag.PhaseCanon
        "UNKNOWN OPERATOR"
        (Text.pack ("Unknown operator (" <> Name.toChars op <> ")"))
        (LabeledSpan region "unknown operator" SpanPrimary)
        (extractReportMessage (toReport source (NotFoundBinop region op locals)))
    )

-- | Add structured suggestions for operators.
addBinopSuggestions :: Ann.Region -> Name.Name -> Set.Set Name.Name -> Diagnostic -> Diagnostic
addBinopSuggestions region op locals diag =
  foldr Diag.addSuggestion diag (take 2 (fmap (toNameSuggestion region) sorted))
  where
    sorted = Suggest.sort (Name.toChars op) Name.toChars (Set.toList locals)

-- | Build a diagnostic for using a record constructor in a pattern.
patternHasRecordCtorDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
patternHasRecordCtorDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 28)
    Diag.SError
    Diag.PhaseCanon
    "BAD PATTERN"
    (Text.pack ("Record constructor `" <> Name.toChars name <> "` cannot be used in a pattern"))
    (LabeledSpan region "record ctor in pattern" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("You can construct records by using `" <> Name.toChars name <> "` as a function, but it is not available in pattern matching like this:"), Doc.reflow "I recommend matching the record as a variable and unpacking it later."))

-- | Build a diagnostic for an invalid port payload type.
--
-- Delegates the message Doc to 'toReport' to reuse the payload-kind message logic.
portPayloadInvalidDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> InvalidPayload -> Diagnostic
portPayloadInvalidDiagnostic source region portName invalidPayload =
  Diag.makeDiagnostic
    (EC.canonError 29)
    Diag.SError
    Diag.PhaseCanon
    "PORT ERROR"
    (Text.pack ("Port `" <> Name.toChars portName <> "` has an invalid payload type"))
    (LabeledSpan region "invalid port payload" SpanPrimary)
    (portPayloadMessage source region portName invalidPayload)

-- | Build the message Doc for a port payload error.
portPayloadMessage :: Code.Source -> Ann.Region -> Name.Name -> InvalidPayload -> Doc.Doc
portPayloadMessage source region portName invalidPayload =
  Code.toSnippet source region Nothing
    ( Doc.reflow ("The `" <> Name.toChars portName <> "` port is trying to transmit " <> portPayloadKind invalidPayload <> ":"),
      Doc.stack [portPayloadElaboration invalidPayload, Doc.link "Hint" "Ports are not a traditional FFI, so if you have tons of annoying ports, definitely read" "ports" "to learn how they are meant to work. They require a different mindset!"]
    )

-- | Name the kind of invalid payload for use in the error message.
portPayloadKind :: InvalidPayload -> String
portPayloadKind invalidPayload =
  case invalidPayload of
    ExtendedRecord -> "an extended record"
    Function -> "a function"
    TypeVariable _ -> "an unspecified type"
    UnsupportedType name -> "a `" <> Name.toChars name <> "` value"

-- | Provide the elaboration sentence for an invalid payload type.
portPayloadElaboration :: InvalidPayload -> Doc.Doc
portPayloadElaboration invalidPayload =
  case invalidPayload of
    ExtendedRecord ->
      Doc.reflow "But the exact shape of the record must be known at compile time. No type variables!"
    Function ->
      Doc.reflow "But functions cannot be sent in and out ports. If we allowed functions in from JS they may perform some side-effects. If we let functions out, they could produce incorrect results because Canopy optimizations assume there are no side-effects."
    TypeVariable name ->
      Doc.reflow ("But type variables like `" <> Name.toChars name <> "` cannot flow through ports. I need to know exactly what type of data I am getting, so I can guarantee that unexpected data cannot sneak in and crash the Canopy program.")
    UnsupportedType _ ->
      Doc.stack [Doc.reflow "I cannot handle that. The types that CAN flow in and out of Canopy include:", Doc.indent 4 (Doc.reflow "Ints, Floats, Bools, Strings, Maybes, Lists, Arrays, tuples, records, and JSON values."), Doc.reflow "Since JSON values can flow through, you can use JSON encoders and decoders to allow other types through as well. More advanced users often just do everything with encoders and decoders for more control and better errors."]

-- | Build a diagnostic for an invalid port type structure.
--
-- Delegates the message Doc to 'toReport' to reuse the port-problem hints.
portTypeInvalidDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> PortProblem -> Diagnostic
portTypeInvalidDiagnostic source region name portProblem =
  Diag.makeDiagnostic
    (EC.canonError 30)
    Diag.SError
    Diag.PhaseCanon
    "BAD PORT"
    (Text.pack ("Port `" <> Name.toChars name <> "` has an invalid type structure"))
    (LabeledSpan region "invalid port type" SpanPrimary)
    (extractReportMessage (toReport source (PortTypeInvalid region name portProblem)))

-- | Build a diagnostic for a recursive type alias.
--
-- Delegates the message Doc to the existing 'aliasRecursionReport' helper.
recursiveAliasDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Src.Type -> [Name.Name] -> Diagnostic
recursiveAliasDiagnostic source region name args tipe others =
  Diag.makeDiagnostic
    (EC.canonError 31)
    Diag.SError
    Diag.PhaseCanon
    "ALIAS PROBLEM"
    (Text.pack ("Type alias `" <> Name.toChars name <> "` is recursive"))
    (LabeledSpan region "recursive alias" SpanPrimary)
    (extractReportMessage (aliasRecursionReport source region name args tipe others))

-- | Build a diagnostic for a recursive value or function declaration.
--
-- Delegates the message Doc to 'toReport' to reuse the cycle explanation.
recursiveDeclDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Diagnostic
recursiveDeclDiagnostic source region name names =
  Diag.makeDiagnostic
    (EC.canonError 32)
    Diag.SError
    Diag.PhaseCanon
    "CYCLIC DEFINITION"
    (Text.pack ("Value `" <> Name.toChars name <> "` is defined in terms of itself"))
    (LabeledSpan region "cyclic definition" SpanPrimary)
    (extractReportMessage (toReport source (RecursiveDecl region name names)))

-- | Build a diagnostic for a cyclic value in a let expression.
--
-- Delegates the message Doc to 'toReport' to reuse the cycle explanation.
recursiveLetDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Diagnostic
recursiveLetDiagnostic source region name names =
  Diag.makeDiagnostic
    (EC.canonError 33)
    Diag.SError
    Diag.PhaseCanon
    "CYCLIC VALUE"
    (Text.pack ("Let binding `" <> Name.toChars name <> "` is defined in terms of itself"))
    (LabeledSpan region "cyclic let binding" SpanPrimary)
    (extractReportMessage (toReport source (RecursiveLet (Ann.At region name) names)))

-- | Build a diagnostic for a shadowed variable binding.
--
-- Delegates the message Doc to 'toReport' to reuse the shadowing advice link.
shadowingDiagnostic :: Code.Source -> Name.Name -> Ann.Region -> Ann.Region -> Diagnostic
shadowingDiagnostic source name r1 r2 =
  Diag.makeDiagnostic
    (EC.canonError 34)
    Diag.SError
    Diag.PhaseCanon
    "SHADOWING"
    (Text.pack ("Variable `" <> Name.toChars name <> "` shadows an outer binding"))
    (LabeledSpan r2 "shadowing binding" SpanPrimary)
    (extractReportMessage (toReport source (Shadowing name r1 r2)))

-- | Build a diagnostic for a tuple with more than three elements.
tupleLargerThanThreeDiagnostic :: Code.Source -> Ann.Region -> Diagnostic
tupleLargerThanThreeDiagnostic source region =
  Diag.makeDiagnostic
    (EC.canonError 35)
    Diag.SError
    Diag.PhaseCanon
    "BAD TUPLE"
    "Tuples can have at most three items"
    (LabeledSpan region "tuple too large" SpanPrimary)
    (extractReportMessage (toReport source (TupleLargerThanThree region)))

-- | Build a diagnostic for unbound type variables in a union type.
--
-- Delegates the message Doc to the existing 'unboundTypeVars' helper.
typeVarsUnboundInUnionDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> (Name.Name, Ann.Region) -> [(Name.Name, Ann.Region)] -> Diagnostic
typeVarsUnboundInUnionDiagnostic source unionRegion typeName allVars unbound unbounds =
  Diag.makeDiagnostic
    (EC.canonError 36)
    Diag.SError
    Diag.PhaseCanon
    "UNBOUND TYPE VARIABLE"
    (Text.pack ("Type `" <> Name.toChars typeName <> "` uses unbound type variables"))
    (LabeledSpan unionRegion "unbound type variable" SpanPrimary)
    (extractReportMessage (unboundTypeVars source unionRegion ["type"] typeName allVars unbound unbounds))

-- | Build a diagnostic for type variable problems in a type alias.
--
-- Delegates the message Doc to 'toReport' to reuse the complex alias-variable logic.
typeVarsMessedUpInAliasDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> [(Name.Name, Ann.Region)] -> [(Name.Name, Ann.Region)] -> Diagnostic
typeVarsMessedUpInAliasDiagnostic source aliasRegion typeName allVars unusedVars unboundVars =
  Diag.makeDiagnostic
    (EC.canonError 37)
    Diag.SError
    Diag.PhaseCanon
    "TYPE VARIABLE PROBLEMS"
    (Text.pack ("Type alias `" <> Name.toChars typeName <> "` has type variable problems"))
    (LabeledSpan aliasRegion "type variable problem" SpanPrimary)
    (extractReportMessage (toReport source (TypeVarsMessedUpInAlias aliasRegion typeName allVars unusedVars unboundVars)))

-- | Build a diagnostic for a missing FFI file.
ffiFileNotFoundDiagnostic :: Code.Source -> Ann.Region -> FilePath -> Diagnostic
ffiFileNotFoundDiagnostic source region filePath =
  Diag.makeDiagnostic
    (EC.canonError 38)
    Diag.SError
    Diag.PhaseCanon
    "FFI FILE NOT FOUND"
    (Text.pack ("Cannot find FFI file: " <> filePath))
    (LabeledSpan region "FFI file not found" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("Cannot find FFI file: " <> filePath), Doc.reflow "Make sure the file exists and the path is correct."))

-- | Build a diagnostic for an FFI file that took too long to read.
ffiFileTimeoutDiagnostic :: Code.Source -> Ann.Region -> FilePath -> Int -> Diagnostic
ffiFileTimeoutDiagnostic source region filePath timeout =
  Diag.makeDiagnostic
    (EC.canonError 39)
    Diag.SError
    Diag.PhaseCanon
    "FFI FILE TIMEOUT"
    (Text.pack ("Timeout reading FFI file: " <> filePath))
    (LabeledSpan region "FFI file timeout" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("Timeout reading FFI file: " <> filePath <> " after " <> show timeout <> "ms"), Doc.reflow "The file may be too large or there may be a filesystem issue."))

-- | Build a diagnostic for an FFI file that failed to parse.
ffiParseErrorDiagnostic :: Code.Source -> Ann.Region -> FilePath -> String -> Diagnostic
ffiParseErrorDiagnostic source region filePath parseErr =
  Diag.makeDiagnostic
    (EC.canonError 40)
    Diag.SError
    Diag.PhaseCanon
    "FFI PARSE ERROR"
    (Text.pack ("Error parsing FFI file: " <> filePath))
    (LabeledSpan region "FFI parse error" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("Error parsing FFI file: " <> filePath), Doc.reflow ("Parse error: " <> parseErr)))

-- | Build a diagnostic for an FFI path traversal attempt.
ffiPathTraversalDiagnostic :: Code.Source -> Ann.Region -> FilePath -> String -> Diagnostic
ffiPathTraversalDiagnostic source region filePath reason =
  Diag.makeDiagnostic
    (EC.canonError 49)
    Diag.SError
    Diag.PhaseCanon
    "FFI PATH ERROR"
    (Text.pack ("FFI path not allowed: " <> filePath))
    (LabeledSpan region "invalid FFI path" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("The foreign import path is not allowed: " <> filePath), Doc.reflow reason))

-- | Build a diagnostic for an invalid type in an FFI file.
ffiInvalidTypeDiagnostic :: Code.Source -> Ann.Region -> FilePath -> Name.Name -> String -> Diagnostic
ffiInvalidTypeDiagnostic source region filePath typeName typeErr =
  Diag.makeDiagnostic
    (EC.canonError 41)
    Diag.SError
    Diag.PhaseCanon
    "FFI INVALID TYPE"
    (Text.pack ("Invalid type in FFI file: " <> filePath))
    (LabeledSpan region "FFI invalid type" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("Invalid type in FFI file: " <> filePath), Doc.reflow ("Type " <> Name.toChars typeName <> ": " <> typeErr)))

-- | Build a diagnostic for a missing type annotation in an FFI file.
ffiMissingAnnotationDiagnostic :: Code.Source -> Ann.Region -> FilePath -> Name.Name -> Diagnostic
ffiMissingAnnotationDiagnostic source region filePath funcName =
  Diag.makeDiagnostic
    (EC.canonError 42)
    Diag.SError
    Diag.PhaseCanon
    "FFI MISSING ANNOTATION"
    (Text.pack ("Missing type annotation in FFI file: " <> filePath))
    (LabeledSpan region "FFI missing annotation" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("Missing type annotation in FFI file: " <> filePath), Doc.reflow ("Function " <> Name.toChars funcName <> " needs a type annotation.")))

-- | Build a diagnostic for a circular dependency in FFI files.
ffiCircularDependencyDiagnostic :: Code.Source -> Ann.Region -> FilePath -> [FilePath] -> Diagnostic
ffiCircularDependencyDiagnostic source region filePath deps =
  Diag.makeDiagnostic
    (EC.canonError 43)
    Diag.SError
    Diag.PhaseCanon
    "FFI CIRCULAR DEPENDENCY"
    (Text.pack ("Circular dependency in FFI file: " <> filePath))
    (LabeledSpan region "FFI circular dependency" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("Circular dependency detected in FFI file: " <> filePath), Doc.reflow ("Dependency chain: " <> show deps)))

-- | Build a diagnostic for an FFI type that is not in scope.
ffiTypeNotFoundDiagnostic :: Code.Source -> Ann.Region -> FilePath -> Name.Name -> String -> [Name.Name] -> Diagnostic
ffiTypeNotFoundDiagnostic source region filePath typeName typeErr suggestions =
  Diag.makeDiagnostic
    (EC.canonError 44)
    Diag.SError
    Diag.PhaseCanon
    "FFI TYPE NOT FOUND"
    (Text.pack ("Unknown type `" <> Name.toChars typeName <> "` in FFI file: " <> filePath))
    (LabeledSpan region "FFI type not found" SpanPrimary)
    (Code.toSnippet source region Nothing (Doc.reflow ("Unknown type in FFI file: " <> filePath), hintDoc))
  where
    nearbyNames = fmap Name.toChars (take 4 (Suggest.sort (Name.toChars typeName) Name.toChars suggestions))
    hintDoc = Doc.stack
      [ Doc.reflow ("The type `" <> Name.toChars typeName <> "` is not in scope: " <> typeErr)
      , case fmap Doc.fromChars nearbyNames of
          [] -> Doc.reflow "Make sure this type is imported or defined in your module."
          [alt] -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
          alts -> Doc.stack ["These types seem close though:", Doc.indent 4 (Doc.vcat (fmap Doc.dullyellow alts))]
      ]

-- | Build a diagnostic for a lazy import referencing a non-existent module.
lazyImportNotFoundDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Diagnostic
lazyImportNotFoundDiagnostic source region name suggestions =
  Diag.makeDiagnostic
    (EC.canonError 45)
    Diag.SError
    Diag.PhaseCanon
    "LAZY IMPORT NOT FOUND"
    (Text.pack ("Cannot find module `" <> Name.toChars name <> "` for lazy import"))
    (LabeledSpan region "module not found" SpanPrimary)
    (extractReportMessage (toReport source (LazyImportNotFound region name suggestions)))

-- | Build a diagnostic for a lazy import of a core/stdlib module.
lazyImportCoreModuleDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
lazyImportCoreModuleDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 46)
    Diag.SError
    Diag.PhaseCanon
    "BAD LAZY IMPORT"
    (Text.pack ("Core module `" <> Name.toChars name <> "` cannot be lazy-imported"))
    (LabeledSpan region "core module" SpanPrimary)
    (extractReportMessage (toReport source (LazyImportCoreModule region name)))

-- | Build a diagnostic for a lazy import inside a package context.
lazyImportInPackageDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
lazyImportInPackageDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 47)
    Diag.SError
    Diag.PhaseCanon
    "BAD LAZY IMPORT"
    (Text.pack ("Lazy import of `" <> Name.toChars name <> "` is not allowed in packages"))
    (LabeledSpan region "lazy import in package" SpanPrimary)
    (extractReportMessage (toReport source (LazyImportInPackage region name)))

-- | Build a diagnostic for a module lazy-importing itself.
lazyImportSelfDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
lazyImportSelfDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 48)
    Diag.SError
    Diag.PhaseCanon
    "BAD LAZY IMPORT"
    (Text.pack ("Module `" <> Name.toChars name <> "` cannot lazy-import itself"))
    (LabeledSpan region "self lazy import" SpanPrimary)
    (extractReportMessage (toReport source (LazyImportSelf region name)))

-- | Build a diagnostic for a lazy import of an internal kernel module.
lazyImportKernelDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> Diagnostic
lazyImportKernelDiagnostic source region name =
  Diag.makeDiagnostic
    (EC.canonError 49)
    Diag.SError
    Diag.PhaseCanon
    "BAD LAZY IMPORT"
    (Text.pack ("Kernel module `" <> Name.toChars name <> "` cannot be lazy-imported"))
    (LabeledSpan region "kernel module" SpanPrimary)
    (extractReportMessage (toReport source (LazyImportKernel region name)))

-- BAD TYPE VARIABLES

unboundTypeVars :: Code.Source -> Ann.Region -> [Doc.Doc] -> Name.Name -> [Name.Name] -> (Name.Name, Ann.Region) -> [(Name.Name, Ann.Region)] -> Report.Report
unboundTypeVars source declRegion tipe typeName allVars (unboundVar, varRegion) unboundVars =
  let backQuote name =
        "`" <> Doc.fromName name <> "`"

      (title, subRegion, overview) =
        case fmap fst unboundVars of
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
   in Report.Report title declRegion [] $
        Code.toSnippet
          source
          declRegion
          subRegion
          ( Doc.fillSep overview,
            Doc.stack
              [ Doc.reflow "You probably need to change the declaration to something like this:",
                Doc.indent 4 . Doc.hsep $ (tipe <> ([Doc.fromName typeName] <> (fmap Doc.fromName allVars <> (fmap (Doc.green . Doc.fromName) (unboundVar : fmap fst unboundVars) <> ["=", "..."])))),
                Doc.reflow
                  ( "Why? Well, imagine one `"
                      <> ( Name.toChars typeName
                             <> ( "` where `"
                                    <> ( Name.toChars unboundVar
                                           <> "` is an Int and another where it is a Bool. When we explicitly list the type\
                                              \ variables, the type checker can see that they are actually different types."
                                       )
                                )
                         )
                  )
              ]
          )

-- NAME CLASH

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

-- AMBIGUOUS NAME

ambiguousName :: Code.Source -> Ann.Region -> Maybe Name.Name -> Name.Name -> ModuleName.Canonical -> OneOrMore.OneOrMore ModuleName.Canonical -> String -> Report.Report
ambiguousName source region maybePrefix name h hs thing =
  let possibleHomes = List.sort (h : OneOrMore.destruct (:) hs)
   in ( Report.Report "AMBIGUOUS NAME" region [] . Code.toSnippet source region Nothing $
          ( case maybePrefix of
              Nothing ->
                let homeToYellowDoc (ModuleName.Canonical _ home) =
                      Doc.dullyellow (Doc.fromName home <> "." <> Doc.fromName name)
                 in ( Doc.reflow ("This usage of `" <> (Name.toChars name <> "` is ambiguous:")),
                      Doc.stack
                        [ Doc.reflow
                            ( "This name is exposed by "
                                <> ( show (length possibleHomes)
                                       <> " of your imports, so I am not\
                                          \ sure which one to use:"
                                   )
                            ),
                          Doc.indent 4 . Doc.vcat $ fmap homeToYellowDoc possibleHomes,
                          Doc.reflow
                            "I recommend using qualified names for imported values. I also recommend having\
                            \ at most one `exposing (..)` per file to make name clashes like this less common\
                            \ in the long run.",
                          Doc.link "Note" "Check out" "imports" "for more info on the import syntax."
                        ]
                    )
              Just prefix ->
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
          )
      )

-- NOT FOUND

notFound :: Code.Source -> Ann.Region -> Maybe Name.Name -> Name.Name -> String -> PossibleNames -> Report.Report
notFound source region maybePrefix name thing (PossibleNames locals quals) =
  let givenName =
        maybe Name.toChars toQualString maybePrefix name

      possibleNames =
        let addQuals prefix localSet allNames =
              Set.foldr (\x xs -> toQualString prefix x : xs) allNames localSet
         in Map.foldrWithKey addQuals (fmap Name.toChars (Set.toList locals)) quals

      nearbyNames =
        take 4 (Suggest.sort givenName id possibleNames)

      toDetails noSuggestionDetails yesSuggestionDetails =
        case nearbyNames of
          [] ->
            Doc.stack
              [ Doc.reflow noSuggestionDetails,
                Doc.link "Hint" "Read" "imports" "to see how `import` declarations work in Canopy."
              ]
          suggestions ->
            Doc.stack
              [ Doc.reflow yesSuggestionDetails,
                (Doc.indent 4 . Doc.vcat) (fmap (Doc.dullyellow . Doc.fromChars) suggestions),
                Doc.link "Hint" "Read" "imports" "to see how `import` declarations work in Canopy."
              ]
   in Report.Report "NAMING ERROR" region nearbyNames $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow ("I cannot find a `" <> (givenName <> ("` " <> (thing <> ":")))),
            case maybePrefix of
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
                      ("The `" <> (Name.toChars prefix <> ("` module does not expose a `" <> (Name.toChars name <> ("` " <> (thing <> "."))))))
                      ("The `" <> (Name.toChars prefix <> ("` module does not expose a `" <> (Name.toChars name <> ("` " <> (thing <> ". These names seem close though:"))))))
          )

toQualString :: Name.Name -> Name.Name -> String
toQualString prefix name =
  Name.toChars prefix <> ("." <> Name.toChars name)

{-- VAR ERROR

varErrorToReport :: VarError -> Report.Report
varErrorToReport (VarError kind name problem suggestions) =
  let
    learnMore orMaybe =
      Doc.reflow $
        orMaybe <> " `import` works different than you expect? Learn all about it here: "
        <> Doc.hintLink "imports"

    namingError overview maybeStarter specializedSuggestions =
      Report.reportDoc "NAMING ERROR" Nothing overview $
        case Doc.maybeYouWant' maybeStarter specializedSuggestions of
          Nothing ->
            learnMore "Maybe"
          Just doc ->
            Doc.stack [ doc, learnMore "Or maybe" ]

    specialNamingError specialHint =
      Report.reportDoc "NAMING ERROR" Nothing (cannotFind kind name) (Doc.hsep specialHint)
  in
  case problem of
    Ambiguous ->
      namingError (ambiguous kind name) Nothing suggestions

    UnknownQualifier qualifier localName ->
      namingError
        (cannotFind kind name)
        (Just $ text $ "No module called `" <> qualifier <> "` has been imported.")
        (map (\modul -> modul <> "." <> localName) suggestions)

    QualifiedUnknown qualifier localName ->
      namingError
        (cannotFind kind name)
        (Just $ text $ "`" <> qualifier <> "` does not expose `" <> localName <> "`.")
        (map (\v -> qualifier <> "." <> v) suggestions)

    FFIFileNotFound region filePath ->
      Report.Report "FFI FILE NOT FOUND" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow $ "Cannot find FFI file: " <> filePath
          , Doc.reflow "Make sure the file exists and the path is correct."
          )
    FFIFileTimeout region filePath timeout ->
      Report.Report "FFI FILE TIMEOUT" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow $ "Timeout reading FFI file: " <> filePath <> " after " <> show timeout <> "ms"
          , Doc.reflow "The file may be too large or there may be a filesystem issue."
          )
    FFIParseError region filePath parseErr ->
      Report.Report "FFI PARSE ERROR" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow $ "Error parsing FFI file: " <> filePath
          , Doc.reflow $ "Parse error: " <> parseErr
          )
    FFIPathTraversal region filePath reason ->
      Report.Report "FFI PATH ERROR" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow $ "The foreign import path is not allowed: " <> filePath
          , Doc.stack
              [ Doc.reflow reason
              , Doc.reflow "FFI source paths must be relative paths within your project directory, ending in .js or .mjs, without '..' components."
              ]
          )
    FFIInvalidType region filePath typeName typeErr ->
      Report.Report "FFI INVALID TYPE" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow $ "Invalid type in FFI file: " <> filePath
          , Doc.reflow $ "Type " <> Name.toChars typeName <> ": " <> typeErr
          )
    FFIMissingAnnotation region filePath funcName ->
      Report.Report "FFI MISSING ANNOTATION" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow $ "Missing type annotation in FFI file: " <> filePath
          , Doc.reflow $ "Function " <> Name.toChars funcName <> " needs a type annotation."
          )
    FFICircularDependency region filePath deps ->
      Report.Report "FFI CIRCULAR DEPENDENCY" region [] $
        Code.toSnippet source region Nothing
          ( Doc.reflow $ "Circular dependency detected in FFI file: " <> filePath
          , Doc.reflow $ "Dependency chain: " <> show deps
          )
    ExposedUnknown ->
      case name of
        "!="  -> specialNamingError (notEqualsHint name)
        "!==" -> specialNamingError (notEqualsHint name)
        "===" -> specialNamingError equalsHint
        "%"   -> specialNamingError modHint
        _     -> namingError (cannotFind kind name) Nothing suggestions

cannotFind :: VarKind -> Text -> [Doc]
cannotFind kind rawName =
  let ( a, thing, name ) = toKindInfo kind rawName in
  [ "Cannot", "find", a, thing, "named", Doc.dullyellow name <> ":" ]

ambiguous :: VarKind -> Text -> [Doc]
ambiguous kind rawName =
  let ( _a, thing, name ) = toKindInfo kind rawName in
  [ "This", "usage", "of", "the", Doc.dullyellow name, thing, "is", "ambiguous." ]

notEqualsHint :: Text -> [Doc]
notEqualsHint op =
  [ "Looking", "for", "the", "“not", "equal”", "operator?", "The", "traditional"
  , Doc.dullyellow $ text $ "(" <> op <> ")"
  , "is", "replaced", "by", Doc.green "(/=)", "in", "Canopy.", "It", "is", "meant"
  , "to", "look", "like", "the", "“not", "equal”", "sign", "from", "math!", "(≠)"
  ]

equalsHint :: [Doc]
equalsHint =
  [ "A", "special", Doc.dullyellow "(===)", "operator", "is", "not", "needed"
  , "in", "Canopy.", "We", "use", Doc.green "(==)", "for", "everything!"
  ]

modHint :: [Doc]
modHint =
  [ "Rather", "than", "a", Doc.dullyellow "(%)", "operator,"
  , "Canopy", "has", "a", Doc.green "modBy", "function."
  , "Learn", "more", "here:"
  , "<https://package.canopy-lang.org/packages/canopy/core/latest/Basics#modBy>"
  ]

-}

-- ARG MISMATCH

_argMismatchReport :: Code.Source -> Ann.Region -> String -> Name.Name -> Int -> Int -> Report.Report
_argMismatchReport source region kind name expected actual =
  let numArgs =
        "too "
          <> (if actual < expected then "few" else "many")
          <> " arguments"
   in Report.Report (fmap Char.toUpper numArgs) region [] $
        Code.toSnippet
          source
          region
          Nothing
          ( Doc.reflow $
              kind <> " " <> Name.toChars name <> " has " <> numArgs <> ".",
            Doc.reflow $
              "Expecting " <> show expected <> ", but got " <> show actual <> "."
          )

-- BAD ALIAS RECURSION

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
                Doc.indent 4 $
                  aliasToUnionDoc name args tipe,
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
