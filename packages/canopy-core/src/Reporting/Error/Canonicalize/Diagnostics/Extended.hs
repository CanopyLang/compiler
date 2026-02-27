{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Canonicalize.Diagnostics.Extended - Extended diagnostic builders
--
-- Contains diagnostic builders for: ports, recursive definitions, shadowing,
-- tuples, type variables, FFI errors, and lazy imports.
--
-- This is a sub-module of "Reporting.Error.Canonicalize.Diagnostics" and is
-- re-exported from there. Users should import the parent module directly.
--
-- @since 0.19.1
module Reporting.Error.Canonicalize.Diagnostics.Extended
  ( -- * Ports
    portPayloadInvalidDiagnostic,
    portPayloadMessage,
    portPayloadKind,
    portPayloadElaboration,
    portTypeInvalidDiagnostic,
    -- * Recursive definitions
    recursiveAliasDiagnostic,
    recursiveDeclDiagnostic,
    recursiveLetDiagnostic,
    -- * Shadowing / tuples
    shadowingDiagnostic,
    tupleLargerThanThreeDiagnostic,
    -- * Type variables
    typeVarsUnboundInUnionDiagnostic,
    typeVarsMessedUpInAliasDiagnostic,
    -- * FFI
    ffiFileNotFoundDiagnostic,
    ffiFileTimeoutDiagnostic,
    ffiParseErrorDiagnostic,
    ffiPathTraversalDiagnostic,
    ffiInvalidTypeDiagnostic,
    ffiMissingAnnotationDiagnostic,
    ffiCircularDependencyDiagnostic,
    ffiTypeNotFoundDiagnostic,
    -- * Lazy imports
    lazyImportNotFoundDiagnostic,
    lazyImportCoreModuleDiagnostic,
    lazyImportInPackageDiagnostic,
    lazyImportSelfDiagnostic,
    lazyImportKernelDiagnostic,
  )
where

import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import qualified Data.Text as Text
import qualified Reporting.Annotation as Ann
import Reporting.Diagnostic (Diagnostic, LabeledSpan (..), SpanStyle (..))
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.Doc as Doc
import qualified Reporting.Error.Canonicalize.Helpers as Helpers
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code
import qualified Reporting.Suggest as Suggest

-- ---------------------------------------------------------------------------
-- Ports
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for an invalid port payload type.
portPayloadInvalidDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> String -> Doc.Doc -> Diagnostic
portPayloadInvalidDiagnostic source region portName kindStr elaboration =
  Diag.makeDiagnostic
    (EC.canonError 29)
    Diag.SError
    Diag.PhaseCanon
    "PORT ERROR"
    (Text.pack ("Port `" <> Name.toChars portName <> "` has an invalid payload type"))
    (LabeledSpan region "invalid port payload" SpanPrimary)
    (portPayloadMessage source region portName kindStr elaboration)

-- | Build the message Doc for a port payload error.
portPayloadMessage :: Code.Source -> Ann.Region -> Name.Name -> String -> Doc.Doc -> Doc.Doc
portPayloadMessage source region portName kindStr elaboration =
  Code.toSnippet source region Nothing
    ( Doc.reflow ("The `" <> Name.toChars portName <> "` port is trying to transmit " <> kindStr <> ":"),
      Doc.stack [elaboration, Doc.link "Hint" "Ports are not a traditional FFI, so if you have tons of annoying ports, definitely read" "ports" "to learn how they are meant to work. They require a different mindset!"]
    )

-- | Name the kind of invalid payload for use in the error message.
portPayloadKind :: String -> Name.Name -> String
portPayloadKind tag name =
  case tag of
    "extended-record" -> "an extended record"
    "function" -> "a function"
    "type-variable" -> "an unspecified type"
    _ -> "a `" <> Name.toChars name <> "` value"

-- | Provide the elaboration Doc for an invalid payload type.
portPayloadElaboration :: String -> Name.Name -> Doc.Doc
portPayloadElaboration tag name =
  case tag of
    "extended-record" ->
      Doc.reflow "But the exact shape of the record must be known at compile time. No type variables!"
    "function" ->
      Doc.reflow "But functions cannot be sent in and out ports. If we allowed functions in from JS they may perform some side-effects. If we let functions out, they could produce incorrect results because Canopy optimizations assume there are no side-effects."
    "type-variable" ->
      Doc.reflow ("But type variables like `" <> Name.toChars name <> "` cannot flow through ports. I need to know exactly what type of data I am getting, so I can guarantee that unexpected data cannot sneak in and crash the Canopy program.")
    _ ->
      Doc.stack [Doc.reflow "I cannot handle that. The types that CAN flow in and out of Canopy include:", Doc.indent 4 (Doc.reflow "Ints, Floats, Bools, Strings, Maybes, Lists, Arrays, tuples, records, and JSON values."), Doc.reflow "Since JSON values can flow through, you can use JSON encoders and decoders to allow other types through as well. More advanced users often just do everything with encoders and decoders for more control and better errors."]

-- | Build a diagnostic for an invalid port type structure.
portTypeInvalidDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> String -> Int -> Diagnostic
portTypeInvalidDiagnostic source region name problemTag extraArgs =
  Diag.makeDiagnostic
    (EC.canonError 30)
    Diag.SError
    Diag.PhaseCanon
    "BAD PORT"
    (Text.pack ("Port `" <> Name.toChars name <> "` has an invalid type structure"))
    (LabeledSpan region "invalid port type" SpanPrimary)
    (buildPortTypeInvalidMsg source region name problemTag extraArgs)

-- | Build the message Doc for a port-type-invalid error.
buildPortTypeInvalidMsg :: Code.Source -> Ann.Region -> Name.Name -> String -> Int -> Doc.Doc
buildPortTypeInvalidMsg source region name problemTag extraArgs =
  Code.toSnippet source region Nothing
    ( Doc.reflow (fst (portTypeDetails name problemTag extraArgs)),
      Doc.stack
        [ snd (portTypeDetails name problemTag extraArgs),
          Doc.link "Hint" "Read" "ports" "for more advice. For example, do not end up with one port per JS function!"
        ]
    )

-- | Compute the before/after text for a port-type-invalid error.
portTypeDetails :: Name.Name -> String -> Int -> (String, Doc.Doc)
portTypeDetails name problemTag extraArgs =
  case problemTag of
    "cmd-no-arg" ->
      ( "The `" <> Name.toChars name <> "` port cannot be just a command.",
        Doc.reflow "It can be (() -> Cmd msg) if you just need to trigger a JavaScript function, but there is often a better way to set things up."
      )
    "cmd-extra-args" ->
      ( "The `" <> Name.toChars name <> "` port can only send ONE value out to JavaScript.",
        let theseItems
              | extraArgs == 2 = "both of these items into a tuple or record"
              | extraArgs == 3 = "these " <> show extraArgs <> " items into a tuple or record"
              | otherwise = "these " <> show extraArgs <> " items into a record"
         in Doc.reflow ("You can put " <> theseItems <> " to send them out though.")
      )
    "cmd-bad-msg" ->
      ( "The `" <> Name.toChars name <> "` port cannot send any messages to the `update` function.",
        Doc.reflow "It must produce a (Cmd msg) type. Notice the lower case `msg` type variable. The command will trigger some JS code, but it will not send anything particular back to Canopy."
      )
    "sub-bad" ->
      ( "There is something off about this `" <> Name.toChars name <> "` port declaration.",
        Doc.stack
          [ Doc.reflow "To receive messages from JavaScript, you need to define a port like this:",
            (Doc.indent 4 . Doc.dullyellow) . Doc.fromChars $ ("port " <> Name.toChars name <> " : (Int -> msg) -> Sub msg"),
            Doc.reflow "Now every time JS sends an `Int` to this port, it is converted to a `msg`. And if you subscribe, those `msg` values will be piped into your `update` function. The only thing you can customize here is the `Int` type."
          ]
      )
    _ ->
      ( "I am confused about the `" <> Name.toChars name <> "` port declaration.",
        Doc.reflow "Ports need to produce a command (Cmd) or a subscription (Sub) but this is neither. I do not know how to handle this."
      )

-- ---------------------------------------------------------------------------
-- Recursive definitions
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for a recursive type alias.
recursiveAliasDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Src.Type -> [Name.Name] -> Diagnostic
recursiveAliasDiagnostic source region name args tipe others =
  Diag.makeDiagnostic
    (EC.canonError 31)
    Diag.SError
    Diag.PhaseCanon
    "ALIAS PROBLEM"
    (Text.pack ("Type alias `" <> Name.toChars name <> "` is recursive"))
    (LabeledSpan region "recursive alias" SpanPrimary)
    (Helpers.extractReportMessage (Helpers.aliasRecursionReport source region name args tipe others))

-- | Build a diagnostic for a recursive value or function declaration.
recursiveDeclDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Diagnostic
recursiveDeclDiagnostic source region name names =
  Diag.makeDiagnostic
    (EC.canonError 32)
    Diag.SError
    Diag.PhaseCanon
    "CYCLIC DEFINITION"
    (Text.pack ("Value `" <> Name.toChars name <> "` is defined in terms of itself"))
    (LabeledSpan region "cyclic definition" SpanPrimary)
    (buildRecursiveDeclMsg source region name names)

-- | Build the message Doc for a recursive-decl error.
buildRecursiveDeclMsg :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Doc.Doc
buildRecursiveDeclMsg source region name names =
  let makeTheory question details =
        Doc.fillSep (fmap (Doc.dullyellow . Doc.fromChars) (words question) <> fmap Doc.fromChars (words details))
   in Code.toSnippet source region Nothing $
        case names of
          [] ->
            ( Doc.reflow ("The `" <> Name.toChars name <> "` value is defined directly in terms of itself, causing an infinite loop."),
              Doc.stack
                [ makeTheory "Are you trying to mutate a variable?" ("Canopy does not have mutation, so when I see " <> Name.toChars name <> " defined in terms of " <> Name.toChars name <> ", I treat it as a recursive definition. Try giving the new value a new name!"),
                  makeTheory "Maybe you DO want a recursive value?" ("To define " <> Name.toChars name <> " we need to know what " <> Name.toChars name <> " is, so let's expand it. Wait, but now we need to know what " <> Name.toChars name <> " is, so let's expand it... This will keep going infinitely!"),
                  Doc.link "Hint" "The root problem is often a typo in some variable name, but I recommend reading" "bad-recursion" "for more detailed advice, especially if you actually do need a recursive value."
                ]
            )
          _ ->
            ( Doc.reflow ("The `" <> Name.toChars name <> "` definition is causing a very tricky infinite loop."),
              Doc.stack
                [ Doc.reflow ("The `" <> Name.toChars name <> "` value depends on itself through the following chain of definitions:"),
                  Doc.cycle 4 name names,
                  Doc.link "Hint" "The root problem is often a typo in some variable name, but I recommend reading" "bad-recursion" "for more detailed advice, especially if you actually do want mutually recursive values."
                ]
            )

-- | Build a diagnostic for a cyclic value in a let expression.
recursiveLetDiagnostic :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Diagnostic
recursiveLetDiagnostic source region name names =
  Diag.makeDiagnostic
    (EC.canonError 33)
    Diag.SError
    Diag.PhaseCanon
    "CYCLIC VALUE"
    (Text.pack ("Let binding `" <> Name.toChars name <> "` is defined in terms of itself"))
    (LabeledSpan region "cyclic let binding" SpanPrimary)
    (buildRecursiveLetMsg source region name names)

-- | Build the message Doc for a recursive-let error.
buildRecursiveLetMsg :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Doc.Doc
buildRecursiveLetMsg source region name names =
  let makeTheory question details =
        Doc.fillSep (fmap (Doc.dullyellow . Doc.fromChars) (words question) <> fmap Doc.fromChars (words details))
   in Code.toSnippet source region Nothing $
        case names of
          [] ->
            ( Doc.reflow ("The `" <> Name.toChars name <> "` value is defined directly in terms of itself, causing an infinite loop."),
              Doc.stack
                [ makeTheory "Are you trying to mutate a variable?" ("Canopy does not have mutation, so when I see " <> Name.toChars name <> " defined in terms of " <> Name.toChars name <> ", I treat it as a recursive definition. Try giving the new value a new name!"),
                  makeTheory "Maybe you DO want a recursive value?" ("To define " <> Name.toChars name <> " we need to know what " <> Name.toChars name <> " is, so let's expand it. Wait, but now we need to know what " <> Name.toChars name <> " is, so let's expand it... This will keep going infinitely!"),
                  Doc.link "Hint" "The root problem is often a typo in some variable name, but I recommend reading" "bad-recursion" "for more detailed advice, especially if you actually do need a recursive value."
                ]
            )
          _ ->
            ( Doc.reflow "I do not allow cyclic values in `let` expressions.",
              Doc.stack
                [ Doc.reflow ("The `" <> Name.toChars name <> "` value depends on itself through the following chain of definitions:"),
                  Doc.cycle 4 name names,
                  Doc.link "Hint" "The root problem is often a typo in some variable name, but I recommend reading" "bad-recursion" "for more detailed advice, especially if you actually do want mutually recursive values."
                ]
            )

-- ---------------------------------------------------------------------------
-- Shadowing / tuples
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for a shadowed variable binding.
shadowingDiagnostic :: Code.Source -> Name.Name -> Ann.Region -> Ann.Region -> Diagnostic
shadowingDiagnostic source name r1 r2 =
  Diag.makeDiagnostic
    (EC.canonError 34)
    Diag.SError
    Diag.PhaseCanon
    "SHADOWING"
    (Text.pack ("Variable `" <> Name.toChars name <> "` shadows an outer binding"))
    (LabeledSpan r2 "shadowing binding" SpanPrimary)
    (buildShadowingMsg source name r1 r2)

-- | Build the message Doc for a shadowing error.
buildShadowingMsg :: Code.Source -> Name.Name -> Ann.Region -> Ann.Region -> Doc.Doc
buildShadowingMsg source name r1 r2 =
  Code.toPair
    source
    r1
    r2
    ("These variables cannot have the same name:", advice)
    (Doc.reflow ("The name `" <> Name.toChars name <> "` is first defined here:"), "But then it is defined AGAIN over here:", advice)
  where
    advice =
      Doc.stack
        [ Doc.reflow "Think of a more helpful name for one of them and you should be all set!",
          Doc.link "Note" "Linters advise against shadowing, so Canopy makes \"best practices\" the default. Read" "shadowing" "for more details on this choice."
        ]

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
    (Code.toSnippet source region Nothing
      ( "I only accept tuples with two or three items. This has too many:",
        Doc.stack
          [ Doc.reflow "I recommend switching to records. Each item will be named, and you can use the `point.x` syntax to access them.",
            Doc.link "Note" "Read" "tuples" "for more comprehensive advice on working with large chunks of data in Canopy."
          ]
      ))

-- ---------------------------------------------------------------------------
-- Type variables
-- ---------------------------------------------------------------------------

-- | Build a diagnostic for unbound type variables in a union type.
typeVarsUnboundInUnionDiagnostic ::
  Code.Source ->
  Ann.Region ->
  Name.Name ->
  [Name.Name] ->
  (Name.Name, Ann.Region) ->
  [(Name.Name, Ann.Region)] ->
  Diagnostic
typeVarsUnboundInUnionDiagnostic source unionRegion typeName allVars unbound unbounds =
  Diag.makeDiagnostic
    (EC.canonError 36)
    Diag.SError
    Diag.PhaseCanon
    "UNBOUND TYPE VARIABLE"
    (Text.pack ("Type `" <> Name.toChars typeName <> "` uses unbound type variables"))
    (LabeledSpan unionRegion "unbound type variable" SpanPrimary)
    (Helpers.extractReportMessage (Helpers.unboundTypeVars source unionRegion ["type"] typeName allVars unbound unbounds))

-- | Build a diagnostic for type variable problems in a type alias.
typeVarsMessedUpInAliasDiagnostic ::
  Code.Source ->
  Ann.Region ->
  Name.Name ->
  [Name.Name] ->
  [(Name.Name, Ann.Region)] ->
  [(Name.Name, Ann.Region)] ->
  Diagnostic
typeVarsMessedUpInAliasDiagnostic source aliasRegion typeName allVars unusedVars unboundVars =
  Diag.makeDiagnostic
    (EC.canonError 37)
    Diag.SError
    Diag.PhaseCanon
    "TYPE VARIABLE PROBLEMS"
    (Text.pack ("Type alias `" <> Name.toChars typeName <> "` has type variable problems"))
    (LabeledSpan aliasRegion "type variable problem" SpanPrimary)
    (buildTypeVarsMessedUpMsg source aliasRegion typeName allVars unusedVars unboundVars)

-- | Build the message Doc for a messed-up type variable error.
buildTypeVarsMessedUpMsg :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> [(Name.Name, Ann.Region)] -> [(Name.Name, Ann.Region)] -> Doc.Doc
buildTypeVarsMessedUpMsg source aliasRegion typeName allVars unusedVars unboundVars =
  let unused = fmap fst unusedVars
      unbound = fmap fst unboundVars
      backQuote n = "`" <> Doc.fromName n <> "`"
      theseAreUsed = buildUsedVarsBlurb unbound backQuote
      butTheseAreUnused = buildUnusedVarsBlurb unused backQuote
   in Code.toSnippet source aliasRegion Nothing
        ( Doc.reflow ("Type alias `" <> Name.toChars typeName <> "` has some type variable problems."),
          Doc.stack
            [ Doc.fillSep (theseAreUsed <> butTheseAreUnused),
              Doc.reflow "My guess is that a definition like this will work better:",
              Doc.indent 4 . Doc.hsep $
                ["type", "alias", Doc.fromName typeName]
                  <> fmap Doc.fromName (filter (`notElem` unused) allVars)
                  <> fmap (Doc.green . Doc.fromName) unbound
                  <> ["=", "..."]
            ]
        )

-- | Build the "these are used" part of a messed-up type variable message.
buildUsedVarsBlurb :: [Name.Name] -> (Name.Name -> Doc.Doc) -> [Doc.Doc]
buildUsedVarsBlurb unbound backQuote =
  case unbound of
    [x] ->
      [ "Type", "variable", Doc.dullyellow (backQuote x), "appears", "in", "the", "definition,",
        "but", "I", "do", "not", "see", "it", "declared."
      ]
    _ ->
      ["Type", "variables"] <> (Doc.commaSep "and" Doc.dullyellow (fmap Doc.fromName unbound) <> ["are", "used", "in", "the", "definition,", "but", "I", "do", "not", "see", "them", "declared."])

-- | Build the "but these are unused" part of a messed-up type variable message.
buildUnusedVarsBlurb :: [Name.Name] -> (Name.Name -> Doc.Doc) -> [Doc.Doc]
buildUnusedVarsBlurb unused backQuote =
  case unused of
    [x] ->
      [ "Likewise,", "type", "variable", Doc.dullyellow (backQuote x), "is", "declared,", "but", "not", "used."
      ]
    _ ->
      ["Likewise,", "type", "variables"] <> (Doc.commaSep "and" Doc.dullyellow (fmap Doc.fromName unused) <> ["are", "declared,", "but", "not", "used."])

-- ---------------------------------------------------------------------------
-- FFI
-- ---------------------------------------------------------------------------

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
    (Code.toSnippet source region Nothing (Doc.reflow ("Unknown type in FFI file: " <> filePath), buildFfiTypeNotFoundHint typeName typeErr suggestions))

-- | Build the hint Doc for an FFI type-not-found error.
buildFfiTypeNotFoundHint :: Name.Name -> String -> [Name.Name] -> Doc.Doc
buildFfiTypeNotFoundHint typeName typeErr suggestions =
  let nearbyNames = fmap Name.toChars (take 4 (Suggest.sort (Name.toChars typeName) Name.toChars suggestions))
   in Doc.stack
        [ Doc.reflow ("The type `" <> Name.toChars typeName <> "` is not in scope: " <> typeErr),
          case fmap Doc.fromChars nearbyNames of
            [] -> Doc.reflow "Make sure this type is imported or defined in your module."
            [alt] -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
            alts -> Doc.stack ["These types seem close though:", Doc.indent 4 (Doc.vcat (fmap Doc.dullyellow alts))]
        ]

-- ---------------------------------------------------------------------------
-- Lazy imports
-- ---------------------------------------------------------------------------

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
    (buildLazyImportNotFoundMsg source region name suggestions)

-- | Build the message Doc for a lazy-import-not-found error.
buildLazyImportNotFoundMsg :: Code.Source -> Ann.Region -> Name.Name -> [Name.Name] -> Doc.Doc
buildLazyImportNotFoundMsg source region name suggestions =
  let nearbyNames = fmap Name.toChars (take 4 (Suggest.sort (Name.toChars name) Name.toChars suggestions))
   in Code.toSnippet source region Nothing
        ( Doc.reflow ("I cannot find a `" <> Name.toChars name <> "` module for this lazy import:"),
          case fmap Doc.fromChars nearbyNames of
            [] -> Doc.reflow "Make sure the module exists and is listed in your canopy.json source directories."
            [alt] -> Doc.fillSep ["Maybe", "you", "want", Doc.dullyellow alt, "instead?"]
            alts -> Doc.stack ["These names seem close though:", Doc.indent 4 (Doc.vcat (fmap Doc.dullyellow alts))]
        )

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
    (Code.toSnippet source region Nothing (Doc.reflow ("The `" <> Name.toChars name <> "` module is a core library module:"), Doc.reflow "Core modules like Basics, List, Maybe, Result, String, and Platform are always loaded eagerly. They cannot be lazy-imported because they are required for every Canopy program."))

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
    (Code.toSnippet source region Nothing (Doc.reflow ("You are using `lazy import " <> Name.toChars name <> "` inside a package:"), Doc.reflow "Lazy imports enable code splitting, which only works in applications. Packages must use regular imports so their code can be bundled by the application that depends on them."))

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
    (Code.toSnippet source region Nothing (Doc.reflow ("The module `" <> Name.toChars name <> "` is trying to lazy-import itself:"), Doc.reflow "A module cannot lazily load itself. Remove the `lazy` keyword from this import."))

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
    (Code.toSnippet source region Nothing (Doc.reflow ("The `" <> Name.toChars name <> "` module is an internal kernel module:"), Doc.reflow "Kernel modules are internal to the compiler runtime and cannot be lazy-imported. They are always loaded eagerly as part of the runtime system."))
