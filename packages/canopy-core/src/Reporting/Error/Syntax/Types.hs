{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error type definitions for the Canopy parser.
--
-- This module defines all syntax error ADTs used throughout the parser.
-- Each error type represents a specific parsing context (module headers,
-- declarations, expressions, patterns, types, literals) with detailed
-- position information for precise error reporting.
--
-- Error rendering is handled by sibling modules in @Reporting.Error.Syntax@.
--
-- @since 0.19.1
module Reporting.Error.Syntax.Types
  ( Error (..),
    --
    Module (..),
    Exposing (..),
    --
    Decl (..),
    DeclType (..),
    TypeAlias (..),
    CustomType (..),
    DeclDef (..),
    Port (..),
    --
    Expr (..),
    Record (..),
    Tuple (..),
    List (..),
    Func (..),
    Case (..),
    If (..),
    Let (..),
    Def (..),
    Destruct (..),
    --
    Pattern (..),
    PRecord (..),
    PTuple (..),
    PList (..),
    --
    Type (..),
    TRecord (..),
    TTuple (..),
    --
    Char (..),
    String (..),
    Escape (..),
    Number (..),
    --
    Space (..),
  )
where

import qualified Canopy.ModuleName as ModuleName
import qualified Data.Char as Char
import qualified Canopy.Data.Name as Name
import Data.Word (Word16)
import Parse.Primitives (Col, Row)
import Parse.Symbol (BadOperator (..))
import qualified Reporting.Annotation as Ann
import Prelude hiding (Char, String)

-- ALL SYNTAX ERRORS

data Error
  = ModuleNameUnspecified ModuleName.Raw
  | ModuleNameMismatch ModuleName.Raw (Ann.Located ModuleName.Raw)
  | UnexpectedPort Ann.Region
  | NoPorts Ann.Region
  | NoPortsInPackage (Ann.Located Name.Name)
  | NoPortModulesInPackage Ann.Region
  | NoFFIModulesInPackage Ann.Region
  | NoEffectsOutsideKernel Ann.Region
  | ParseError Module
  deriving (Show)

-- MODULE

data Module
  = ModuleSpace Space Row Col
  | ModuleBadEnd Row Col
  | --
    ModuleProblem Row Col
  | ModuleName Row Col
  | ModuleExposing Exposing Row Col
  | --
    PortModuleProblem Row Col
  | PortModuleName Row Col
  | PortModuleExposing Exposing Row Col
  | --
    FFIModuleProblem Row Col
  | FFIModuleName Row Col
  | FFIModuleExposing Exposing Row Col
  | --
    Effect Row Col
  | --
    FreshLine Row Col
  | --
    ImportStart Row Col
  | ImportName Row Col
  | ImportAs Row Col
  | ImportAlias Row Col
  | ImportExposing Row Col
  | ImportExposingList Exposing Row Col
  | ImportEnd Row Col -- different based on col=1 or if greater
  --
  | ImportIndentName Row Col
  | ImportIndentAlias Row Col
  | ImportIndentExposingList Row Col
  | --
    Infix Row Col
  | --
    Declarations Decl Row Col
  deriving (Show)

data Exposing
  = ExposingSpace Space Row Col
  | ExposingStart Row Col
  | ExposingValue Row Col
  | ExposingOperator Row Col
  | ExposingOperatorReserved BadOperator Row Col
  | ExposingOperatorRightParen Row Col
  | ExposingTypePrivacy Row Col
  | ExposingEnd Row Col
  | --
    ExposingIndentEnd Row Col
  | ExposingIndentValue Row Col
  deriving (Show)

-- DECLARATIONS

data Decl
  = DeclStart Row Col
  | DeclSpace Space Row Col
  | --
    Port Port Row Col
  | DeclType DeclType Row Col
  | DeclDef Name.Name DeclDef Row Col
  | --
    DeclFreshLineAfterDocComment Row Col
  deriving (Show)

data DeclDef
  = DeclDefSpace Space Row Col
  | DeclDefEquals Row Col
  | DeclDefType Type Row Col
  | DeclDefArg Pattern Row Col
  | DeclDefBody Expr Row Col
  | DeclDefNameRepeat Row Col
  | DeclDefNameMatch Name.Name Row Col
  | --
    DeclDefIndentType Row Col
  | DeclDefIndentEquals Row Col
  | DeclDefIndentBody Row Col
  deriving (Show)

data Port
  = PortSpace Space Row Col
  | PortName Row Col
  | PortColon Row Col
  | PortType Type Row Col
  | PortIndentName Row Col
  | PortIndentColon Row Col
  | PortIndentType Row Col
  deriving (Show)

-- TYPE DECLARATIONS

data DeclType
  = DT_Space Space Row Col
  | DT_Name Row Col
  | DT_Alias TypeAlias Row Col
  | DT_Union CustomType Row Col
  | --
    DT_IndentName Row Col
  deriving (Show)

data TypeAlias
  = AliasSpace Space Row Col
  | AliasName Row Col
  | AliasEquals Row Col
  | AliasBody Type Row Col
  | --
    AliasIndentEquals Row Col
  | AliasIndentBody Row Col
  deriving (Show)

data CustomType
  = CT_Space Space Row Col
  | CT_Name Row Col
  | CT_Equals Row Col
  | CT_Bar Row Col
  | CT_Variant Row Col
  | CT_VariantArg Type Row Col
  | --
    CT_IndentEquals Row Col
  | CT_IndentBar Row Col
  | CT_IndentAfterBar Row Col
  | CT_IndentAfterEquals Row Col
  deriving (Show)

-- EXPRESSIONS

data Expr
  = Let Let Row Col
  | Case Case Row Col
  | If If Row Col
  | List List Row Col
  | Record Record Row Col
  | Tuple Tuple Row Col
  | Func Func Row Col
  | --
    Dot Row Col
  | Access Row Col
  | OperatorRight Name.Name Row Col
  | OperatorReserved BadOperator Row Col
  | --
    Start Row Col
  | Char Char Row Col
  | String String Row Col
  | Number Number Row Col
  | Space Space Row Col
  | EndlessShader Row Col
  | ShaderProblem [Char.Char] Row Col
  | IndentOperatorRight Name.Name Row Col
  | EndlessInterpolation Row Col
  | InterpolationExpr Expr Row Col
  | InterpolationClose Row Col
  deriving (Show)

data Record
  = RecordOpen Row Col
  | RecordEnd Row Col
  | RecordField Row Col
  | RecordEquals Row Col
  | RecordExpr Expr Row Col
  | RecordSpace Space Row Col
  | --
    RecordIndentOpen Row Col
  | RecordIndentEnd Row Col
  | RecordIndentField Row Col
  | RecordIndentEquals Row Col
  | RecordIndentExpr Row Col
  deriving (Show)

data Tuple
  = TupleExpr Expr Row Col
  | TupleSpace Space Row Col
  | TupleEnd Row Col
  | TupleOperatorClose Row Col
  | TupleOperatorReserved BadOperator Row Col
  | --
    TupleIndentExpr1 Row Col
  | TupleIndentExprN Row Col
  | TupleIndentEnd Row Col
  deriving (Show)

data List
  = ListSpace Space Row Col
  | ListOpen Row Col
  | ListExpr Expr Row Col
  | ListEnd Row Col
  | --
    ListIndentOpen Row Col
  | ListIndentEnd Row Col
  | ListIndentExpr Row Col
  deriving (Show)

data Func
  = FuncSpace Space Row Col
  | FuncArg Pattern Row Col
  | FuncBody Expr Row Col
  | FuncArrow Row Col
  | --
    FuncIndentArg Row Col
  | FuncIndentArrow Row Col
  | FuncIndentBody Row Col
  deriving (Show)

data Case
  = CaseSpace Space Row Col
  | CaseOf Row Col
  | CasePattern Pattern Row Col
  | CaseArrow Row Col
  | CaseExpr Expr Row Col
  | CaseBranch Expr Row Col
  | --
    CaseIndentOf Row Col
  | CaseIndentExpr Row Col
  | CaseIndentPattern Row Col
  | CaseIndentArrow Row Col
  | CaseIndentBranch Row Col
  | CasePatternAlignment Word16 Row Col
  deriving (Show)

data If
  = IfSpace Space Row Col
  | IfThen Row Col
  | IfElse Row Col
  | IfElseBranchStart Row Col
  | --
    IfCondition Expr Row Col
  | IfThenBranch Expr Row Col
  | IfElseBranch Expr Row Col
  | --
    IfIndentCondition Row Col
  | IfIndentThen Row Col
  | IfIndentThenBranch Row Col
  | IfIndentElseBranch Row Col
  | IfIndentElse Row Col
  deriving (Show)

data Let
  = LetSpace Space Row Col
  | LetIn Row Col
  | LetDefAlignment Word16 Row Col
  | LetDefName Row Col
  | LetDef Name.Name Def Row Col
  | LetDestruct Destruct Row Col
  | LetBody Expr Row Col
  | LetIndentDef Row Col
  | LetIndentIn Row Col
  | LetIndentBody Row Col
  deriving (Show)

data Def
  = DefSpace Space Row Col
  | DefType Type Row Col
  | DefNameRepeat Row Col
  | DefNameMatch Name.Name Row Col
  | DefArg Pattern Row Col
  | DefEquals Row Col
  | DefBody Expr Row Col
  | DefIndentEquals Row Col
  | DefIndentType Row Col
  | DefIndentBody Row Col
  | DefAlignment Word16 Row Col
  deriving (Show)

data Destruct
  = DestructSpace Space Row Col
  | DestructPattern Pattern Row Col
  | DestructEquals Row Col
  | DestructBody Expr Row Col
  | DestructIndentEquals Row Col
  | DestructIndentBody Row Col
  deriving (Show)

-- PATTERNS

data Pattern
  = PRecord PRecord Row Col
  | PTuple PTuple Row Col
  | PList PList Row Col
  | --
    PStart Row Col
  | PChar Char Row Col
  | PString String Row Col
  | PNumber Number Row Col
  | PFloat Word16 Row Col
  | PAlias Row Col
  | PWildcardNotVar Name.Name Int Row Col
  | PSpace Space Row Col
  | --
    PIndentStart Row Col
  | PIndentAlias Row Col
  deriving (Show)

data PRecord
  = PRecordOpen Row Col
  | PRecordEnd Row Col
  | PRecordField Row Col
  | PRecordSpace Space Row Col
  | --
    PRecordIndentOpen Row Col
  | PRecordIndentEnd Row Col
  | PRecordIndentField Row Col
  deriving (Show)

data PTuple
  = PTupleOpen Row Col
  | PTupleEnd Row Col
  | PTupleExpr Pattern Row Col
  | PTupleSpace Space Row Col
  | --
    PTupleIndentEnd Row Col
  | PTupleIndentExpr1 Row Col
  | PTupleIndentExprN Row Col
  deriving (Show)

data PList
  = PListOpen Row Col
  | PListEnd Row Col
  | PListExpr Pattern Row Col
  | PListSpace Space Row Col
  | --
    PListIndentOpen Row Col
  | PListIndentEnd Row Col
  | PListIndentExpr Row Col
  deriving (Show)

-- TYPES

data Type
  = TRecord TRecord Row Col
  | TTuple TTuple Row Col
  | --
    TStart Row Col
  | TSpace Space Row Col
  | --
    TIndentStart Row Col
  deriving (Show)

data TRecord
  = TRecordOpen Row Col
  | TRecordEnd Row Col
  | --
    TRecordField Row Col
  | TRecordColon Row Col
  | TRecordType Type Row Col
  | --
    TRecordSpace Space Row Col
  | --
    TRecordIndentOpen Row Col
  | TRecordIndentField Row Col
  | TRecordIndentColon Row Col
  | TRecordIndentType Row Col
  | TRecordIndentEnd Row Col
  deriving (Show)

data TTuple
  = TTupleOpen Row Col
  | TTupleEnd Row Col
  | TTupleType Type Row Col
  | TTupleSpace Space Row Col
  | --
    TTupleIndentType1 Row Col
  | TTupleIndentTypeN Row Col
  | TTupleIndentEnd Row Col
  deriving (Show)

-- LITERALS

data Char
  = CharEndless
  | CharEscape Escape
  | CharNotString Word16
  deriving (Show)

data String
  = StringEndless_Single
  | StringEndless_Multi
  | StringEscape Escape
  deriving (Show)

data Escape
  = EscapeUnknown
  | BadUnicodeFormat Word16
  | BadUnicodeCode Word16
  | BadUnicodeLength Word16 Int Int
  deriving (Show)

data Number
  = NumberEnd
  | NumberDot Int
  | NumberHexDigit
  | NumberNoLeadingZero
  deriving (Show)

-- MISC

data Space
  = HasTab
  | EndlessMultiComment
  deriving (Show)
