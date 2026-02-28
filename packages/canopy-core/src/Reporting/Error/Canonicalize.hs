{-# LANGUAGE OverloadedStrings #-}

-- | Reporting.Error.Canonicalize - Error types and rendering for canonicalization
--
-- This module defines the 'Error' type covering all errors that can arise during
-- the canonicalization phase of compilation: name resolution, export/import
-- validation, type alias recursion, FFI validation, lazy-import checking, etc.
--
-- Rendering is handled by two sub-modules:
--
-- * "Reporting.Error.Canonicalize.Helpers"     - shared report-building helpers
-- * "Reporting.Error.Canonicalize.Diagnostics" - structured diagnostic builders
--
-- The public interface is unchanged: callers pattern-match on 'Error' and call
-- 'toDiagnostic'.
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
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Reporting.Diagnostic (Diagnostic)
import qualified Reporting.Annotation as Ann
import qualified Reporting.Doc as Doc
import qualified Reporting.Error.Canonicalize.Diagnostics as Diags
import qualified Reporting.ErrorCode as EC
import qualified Reporting.Render.Code as Code

-- ---------------------------------------------------------------------------
-- Error types
-- ---------------------------------------------------------------------------

-- | All errors that can arise during the canonicalization phase.
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

-- | Context for a bad-arity error.
data BadArityContext
  = TypeArity
  | PatternArity
  deriving (Show)

-- | Context for a duplicate pattern variable error.
data DuplicatePatternContext
  = DPLambdaArgs
  | DPFuncArgs Name.Name
  | DPCaseBranch
  | DPLetBinding
  | DPDestruct
  deriving (Show)

-- | The kind of value that an invalid port payload carries.
data InvalidPayload
  = ExtendedRecord
  | Function
  | TypeVariable Name.Name
  | UnsupportedType Name.Name
  deriving (Show)

-- | The specific structural problem with a port type.
data PortProblem
  = CmdNoArg
  | CmdExtraArgs Int
  | CmdBadMsg
  | SubBad
  | NotCmdOrSub
  deriving (Show)

-- | Names that are in-scope when a not-found error occurs.
data PossibleNames = PossibleNames
  { _locals :: Set.Set Name.Name,
    _quals :: Map.Map Name.Name (Set.Set Name.Name)
  }
  deriving (Show)

-- | The syntactic kind of a name that could not be found or exported.
data VarKind
  = BadOp
  | BadVar
  | BadPattern
  | BadType
  deriving (Show)

-- ---------------------------------------------------------------------------
-- toDiagnostic
-- ---------------------------------------------------------------------------

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
      Diags.annotationTooShortDiagnostic source region name index leftovers
    AmbiguousVar region maybePrefix name h hs ->
      Diags.ambiguousNameDiagnostic source region maybePrefix name h hs "variable" (EC.canonError 1)
    AmbiguousType region maybePrefix name h hs ->
      Diags.ambiguousNameDiagnostic source region maybePrefix name h hs "type" (EC.canonError 2)
    AmbiguousVariant region maybePrefix name h hs ->
      Diags.ambiguousNameDiagnostic source region maybePrefix name h hs "variant" (EC.canonError 3)
    AmbiguousBinop region name h hs ->
      Diags.ambiguousNameDiagnostic source region Nothing name h hs "operator" (EC.canonError 4)
    BadArity region badArityContext name expected actual ->
      Diags.badArityDiagnostic source region (arityContextThing badArityContext) name expected actual
    Binop region op1 op2 ->
      Diags.binopDiagnostic source region op1 op2
    DuplicateDecl name r1 r2 ->
      Diags.nameClashDiagnostic source r1 r2 (EC.canonError 7) ("This file has multiple `" <> Name.toChars name <> "` declarations.")
    DuplicateType name r1 r2 ->
      Diags.nameClashDiagnostic source r1 r2 (EC.canonError 8) ("This file defines multiple `" <> Name.toChars name <> "` types.")
    DuplicateCtor name r1 r2 ->
      Diags.nameClashDiagnostic source r1 r2 (EC.canonError 9) ("This file defines multiple `" <> Name.toChars name <> "` type constructors.")
    DuplicateBinop name r1 r2 ->
      Diags.nameClashDiagnostic source r1 r2 (EC.canonError 10) ("This file defines multiple (" <> Name.toChars name <> ") operators.")
    DuplicateField name r1 r2 ->
      Diags.nameClashDiagnostic source r1 r2 (EC.canonError 11) ("This record has multiple `" <> Name.toChars name <> "` fields.")
    DuplicateAliasArg typeName name r1 r2 ->
      Diags.nameClashDiagnostic source r1 r2 (EC.canonError 12) ("The `" <> Name.toChars typeName <> "` type alias has multiple `" <> Name.toChars name <> "` type variables.")
    DuplicateUnionArg typeName name r1 r2 ->
      Diags.nameClashDiagnostic source r1 r2 (EC.canonError 13) ("The `" <> Name.toChars typeName <> "` type has multiple `" <> Name.toChars name <> "` type variables.")
    DuplicatePattern context name r1 r2 ->
      Diags.nameClashDiagnostic source r1 r2 (EC.canonError 14) (dupPatternMsg context name)
    EffectNotFound region name ->
      Diags.effectNotFoundDiagnostic source region name
    EffectFunctionNotFound region name ->
      Diags.effectFunctionNotFoundDiagnostic source region name
    ExportDuplicate name r1 r2 ->
      Diags.exportDuplicateDiagnostic source name r1 r2
    ExportNotFound region kind rawName possibleNames ->
      Diags.exportNotFoundDiagnostic source region (toKindStr kind) rawName possibleNames
    ExportOpenAlias region name ->
      Diags.exportOpenAliasDiagnostic source region name
    ImportCtorByName region ctor tipe ->
      Diags.importCtorByNameDiagnostic source region ctor tipe
    ImportNotFound region name _ ->
      Diags.importNotFoundDiagnostic source region name
    ImportOpenAlias region name ->
      Diags.importOpenAliasDiagnostic source region name
    ImportExposingNotFound region home value possibleNames ->
      Diags.importExposingNotFoundDiagnostic source region home value possibleNames
    NotFoundVar region prefix name (PossibleNames locals quals) ->
      Diags.notFoundDiagnostic source region prefix name "variable" locals quals (EC.canonError 24)
    NotFoundType region prefix name (PossibleNames locals quals) ->
      Diags.notFoundDiagnostic source region prefix name "type" locals quals (EC.canonError 25)
    NotFoundVariant region prefix name (PossibleNames locals quals) ->
      Diags.notFoundDiagnostic source region prefix name "variant" locals quals (EC.canonError 26)
    NotFoundBinop region op locals ->
      Diags.notFoundBinopDiagnostic source region op locals
    PatternHasRecordCtor region name ->
      Diags.patternHasRecordCtorDiagnostic source region name
    PortPayloadInvalid region portName _badType invalidPayload ->
      let (kindStr, elaboration) = portPayloadDetails invalidPayload
       in Diags.portPayloadInvalidDiagnostic source region portName kindStr elaboration
    PortTypeInvalid region name portProblem ->
      let (problemTag, extraArgs) = portProblemTag portProblem
       in Diags.portTypeInvalidDiagnostic source region name problemTag extraArgs
    RecursiveAlias region name args tipe others ->
      Diags.recursiveAliasDiagnostic source region name args tipe others
    RecursiveDecl region name names ->
      Diags.recursiveDeclDiagnostic source region name names
    RecursiveLet (Ann.At region name) names ->
      Diags.recursiveLetDiagnostic source region name names
    Shadowing name r1 r2 ->
      Diags.shadowingDiagnostic source name r1 r2
    TupleLargerThanThree region ->
      Diags.tupleLargerThanThreeDiagnostic source region
    TypeVarsUnboundInUnion unionRegion typeName allVars unbound unbounds ->
      Diags.typeVarsUnboundInUnionDiagnostic source unionRegion typeName allVars unbound unbounds
    TypeVarsMessedUpInAlias aliasRegion typeName allVars unusedVars unboundVars ->
      Diags.typeVarsMessedUpInAliasDiagnostic source aliasRegion typeName allVars unusedVars unboundVars
    FFIFileNotFound region filePath ->
      Diags.ffiFileNotFoundDiagnostic source region filePath
    FFIFileTimeout region filePath timeout ->
      Diags.ffiFileTimeoutDiagnostic source region filePath timeout
    FFIParseError region filePath parseErr ->
      Diags.ffiParseErrorDiagnostic source region filePath parseErr
    FFIPathTraversal region filePath reason ->
      Diags.ffiPathTraversalDiagnostic source region filePath reason
    FFIInvalidType region filePath typeName typeErr ->
      Diags.ffiInvalidTypeDiagnostic source region filePath typeName typeErr
    FFIMissingAnnotation region filePath funcName ->
      Diags.ffiMissingAnnotationDiagnostic source region filePath funcName
    FFICircularDependency region filePath deps ->
      Diags.ffiCircularDependencyDiagnostic source region filePath deps
    FFITypeNotFound region filePath typeName typeErr suggestions ->
      Diags.ffiTypeNotFoundDiagnostic source region filePath typeName typeErr suggestions
    LazyImportNotFound region name suggestions ->
      Diags.lazyImportNotFoundDiagnostic source region name suggestions
    LazyImportCoreModule region name ->
      Diags.lazyImportCoreModuleDiagnostic source region name
    LazyImportInPackage region name ->
      Diags.lazyImportInPackageDiagnostic source region name
    LazyImportSelf region name ->
      Diags.lazyImportSelfDiagnostic source region name
    LazyImportKernel region name ->
      Diags.lazyImportKernelDiagnostic source region name

-- ---------------------------------------------------------------------------
-- Private dispatch helpers
-- ---------------------------------------------------------------------------

arityContextThing :: BadArityContext -> String
arityContextThing TypeArity = "type"
arityContextThing PatternArity = "variant"

dupPatternMsg :: DuplicatePatternContext -> Name.Name -> String
dupPatternMsg context name =
  case context of
    DPLambdaArgs -> "This anonymous function has multiple `" <> Name.toChars name <> "` arguments."
    DPFuncArgs funcName -> "The `" <> Name.toChars funcName <> "` function has multiple `" <> Name.toChars name <> "` arguments."
    DPCaseBranch -> "This `case` pattern has multiple `" <> Name.toChars name <> "` variables."
    DPLetBinding -> "This `let` expression defines `" <> Name.toChars name <> "` more than once!"
    DPDestruct -> "This pattern contains multiple `" <> Name.toChars name <> "` variables."

toKindStr :: VarKind -> String
toKindStr BadOp = "op"
toKindStr BadVar = "var"
toKindStr BadPattern = "pattern"
toKindStr BadType = "type"

portPayloadDetails :: InvalidPayload -> (String, Doc.Doc)
portPayloadDetails payload =
  case payload of
    ExtendedRecord ->
      ( "an extended record",
        Doc.reflow "But the exact shape of the record must be known at compile time. No type variables!"
      )
    Function ->
      ( "a function",
        Doc.reflow "But functions cannot be sent in and out ports. If we allowed functions in from JS they may perform some side-effects. If we let functions out, they could produce incorrect results because Canopy optimizations assume there are no side-effects."
      )
    TypeVariable name ->
      ( "an unspecified type",
        Doc.reflow ("But type variables like `" <> Name.toChars name <> "` cannot flow through ports. I need to know exactly what type of data I am getting, so I can guarantee that unexpected data cannot sneak in and crash the Canopy program.")
      )
    UnsupportedType name ->
      ( "a `" <> Name.toChars name <> "` value",
        Doc.stack
          [ Doc.reflow "I cannot handle that. The types that CAN flow in and out of Canopy include:",
            Doc.indent 4 (Doc.reflow "Ints, Floats, Bools, Strings, Maybes, Lists, Arrays, tuples, records, and JSON values."),
            Doc.reflow "Since JSON values can flow through, you can use JSON encoders and decoders to allow other types through as well. More advanced users often just do everything with encoders and decoders for more control and better errors."
          ]
      )

portProblemTag :: PortProblem -> (String, Int)
portProblemTag problem =
  case problem of
    CmdNoArg -> ("cmd-no-arg", 0)
    CmdExtraArgs n -> ("cmd-extra-args", n)
    CmdBadMsg -> ("cmd-bad-msg", 0)
    SubBad -> ("sub-bad", 0)
    NotCmdOrSub -> ("not-cmd-or-sub", 0)
