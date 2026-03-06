{-# LANGUAGE OverloadedStrings #-}

-- | AST.Canonical.Types - Core type definitions for the Canonical AST
--
-- This internal module contains all data type definitions for the Canonical AST.
-- Types are separated from their serialization instances to enable clean module
-- splitting without circular imports.
--
-- External code should import "AST.Canonical" rather than this module directly.
-- The parent module re-exports all types and ensures serialization instances
-- are in scope.
--
-- @since 0.19.1
module AST.Canonical.Types
  ( -- * Expressions
    Expr,
    Expr_ (..),
    CaseBranch (..),
    FieldUpdate (..),
    CtorOpts (..),
    ArithOp (..),
    BinopKind (..),

    -- * Definitions
    Def (..),
    Decls (..),

    -- * Guards
    GuardInfo (..),

    -- * Patterns
    Pattern,
    Pattern_ (..),
    PatternCtorArg (..),

    -- * Types
    Annotation (..),
    FreeVars,
    Type (..),
    AliasType (..),
    FieldType (..),
    fieldsToList,

    -- * Supertype Bounds
    SupertypeBound (..),

    -- * Variance
    Variance (..),

    -- * Deriving
    DerivingClause (..),
    JsonOptions (..),
    NamingStrategy (..),

    -- * Module Structure
    Module (..),
    Alias (..),
    Binop (..),
    Union (..),
    Ctor (..),
    Exports (..),
    Export (..),
    Effects (..),
    Port (..),
    Manager (Cmd, SubManager, Fx),
  )
where

{- Creating a canonical AST means finding the home module for all variables.
So if you have L.map, you need to figure out that it is from the canopy/core
package in the List module.

In later phases (e.g. type inference, exhaustiveness checking, optimization)
you need to look up additional info from these modules. What is the type?
What are the alternative type constructors? These lookups can be quite costly,
especially in type inference. To reduce costs the canonicalization phase
caches info needed in later phases. This means we no longer build large
dictionaries of metadata with O(log(n)) lookups in those phases. Instead
there is an O(1) read of an existing field! I have tried to mark all
cached data with comments like:

-- CACHE for exhaustiveness
-- CACHE for inference

So it is clear why the data is kept around.
-}

import qualified AST.Source as Src
import qualified AST.Utils.Binop as Binop
import qualified AST.Utils.Shader as Shader
import qualified Canopy.Data.Index as Index
import qualified Canopy.Float as EF
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.String as ES
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Canopy.Data.Name (Name)
import Data.Set (Set)
import Data.Word (Word16)
import qualified Reporting.Annotation as Ann

-- EXPRESSIONS

type Expr =
  Ann.Located Expr_

-- | Arithmetic operator classification.
--
-- Represents the different kinds of arithmetic operators that can be
-- compiled to native JavaScript operators. Each operator has specific
-- semantics and optimization opportunities.
--
-- All operators follow JavaScript semantics for consistency with the
-- runtime environment. Int and Float handling differ according to
-- JavaScript number coercion rules.
--
-- @since 0.19.2
data ArithOp
  = -- | Addition operator (+).
    --
    -- Compiles to JavaScript '+' operator.
    --
    -- Semantics:
    -- * Int + Int -> Int
    -- * Float + anything -> Float
    -- * Int + Float -> Float
    --
    -- Identity: x + 0 = 0 + x = x
    Add
  | -- | Subtraction operator (-).
    --
    -- Compiles to JavaScript '-' operator.
    --
    -- Semantics:
    -- * Int - Int -> Int
    -- * Float - anything -> Float
    -- * Int - Float -> Float
    --
    -- Identity: x - 0 = x
    Sub
  | -- | Multiplication operator (*).
    --
    -- Compiles to JavaScript '*' operator.
    --
    -- Semantics:
    -- * Int * Int -> Int
    -- * Float * anything -> Float
    -- * Int * Float -> Float
    --
    -- Identity: x * 1 = 1 * x = x
    -- Absorption: x * 0 = 0 * x = 0
    Mul
  | -- | Floating-point division operator (/).
    --
    -- Compiles to JavaScript '/' operator.
    --
    -- Semantics:
    -- * Always produces Float result
    -- * Int / Int -> Float
    -- * Division by zero -> Infinity or -Infinity
    --
    -- Identity: x / 1 = x
    -- Zero: 0 / x = 0 (for x /= 0)
    Div
  deriving (Eq, Ord, Show)

-- | Binary operator kind classification.
--
-- Classifies binary operators into native arithmetic operators and
-- custom (user-defined or library) operators. Used during canonicalization
-- to determine whether to generate native operator nodes or function calls.
--
-- @since 0.19.2
data BinopKind
  = -- | Native arithmetic operator.
    --
    -- Operators that compile directly to JavaScript operators for efficiency.
    -- These operators receive special treatment in optimization and code
    -- generation phases.
    --
    -- Includes: +, -, *, /
    NativeArith !ArithOp
  | -- | Custom operator (user-defined or library function).
    --
    -- Operators that remain as function calls in the generated code.
    -- These operators go through standard function call optimization.
    --
    -- Includes: (==), (++), (<|), (|>), (&&), (||), etc.
    UserDefined !Name !ModuleName.Canonical !Name
  deriving (Eq, Show)

-- CACHE Annotations for type inference
data Expr_
  = VarLocal Name
  | VarTopLevel ModuleName.Canonical Name
  | VarKernel Name Name
  | VarForeign ModuleName.Canonical Name Annotation
  | VarCtor CtorOpts ModuleName.Canonical Name Index.ZeroBased Annotation
  | VarDebug ModuleName.Canonical Name Annotation
  | VarOperator Name ModuleName.Canonical Name Annotation -- CACHE real name for optimization
  | Chr ES.String
  | Str ES.String
  | Int Int
  | Float EF.Float
  | List [Expr]
  | Negate Expr
  | -- | Binary operator expression.
    --
    -- Represents binary operators with classification (native vs user-defined).
    -- BinopKind determines compilation strategy, Annotation provides type info,
    -- and the two Expr values are left and right operands.
    --
    -- Native arithmetic operators compile to JavaScript operators for efficiency.
    -- User-defined operators remain as standard function calls.
    --
    -- @since 0.19.2
    BinopOp BinopKind Annotation Expr Expr
  | Lambda [Pattern] Expr
  | Call Expr [Expr]
  | If [(Expr, Expr)] Expr
  | Let Def Expr
  | LetRec [Def] Expr
  | LetDestruct Pattern Expr Expr
  | Case Expr [CaseBranch]
  | Accessor Name
  | Access Expr (Ann.Located Name)
  | Update Name Expr (Map Name FieldUpdate)
  | Record (Map Name Expr)
  | Unit
  | Tuple Expr Expr (Maybe Expr)
  | Shader Shader.Source Shader.Types
  | -- | String interpolation concatenation.
    --
    -- Represents a string interpolation expression like @[i|Hello #{name}!|]@.
    -- Each sub-expression must be a @String@. The optimizer converts this to
    -- a chain of @Basics.append@ calls, producing the same JS as manual @++@.
    --
    -- Unlike the @++@ operator (which uses @appendable@ and accepts both
    -- @String@ and @List@), @StringConcat@ constrains every part to exactly
    -- @String@, providing clearer error messages when non-String values are
    -- used in interpolation holes.
    --
    -- @since 0.19.2
    StringConcat [Expr]
  deriving (Show)

data CaseBranch
  = CaseBranch Pattern Expr
  deriving (Show)

data FieldUpdate
  = FieldUpdate Ann.Region Expr
  deriving (Show)

-- | Constructor optimization classification.
--
-- Determines which code generation optimizations are available
-- for union type constructors.
--
-- @since 0.19.1
data CtorOpts
  = Normal
  | Enum
  | Unbox
  deriving (Eq, Ord, Show)

-- DEFS

data Def
  = Def (Ann.Located Name) [Pattern] Expr
  | TypedDef (Ann.Located Name) FreeVars [(Pattern, Type)] Expr Type
  deriving (Show)

-- GUARDS

-- | Guard function annotation in canonical form.
--
-- When a function is annotated with @guards@, calling it in an @if@
-- condition narrows the argument type in the truthy branch. The narrow
-- type has been canonicalized from the source-level annotation.
--
-- @since 0.20.0
data GuardInfo = GuardInfo
  { _giArgIndex :: !Int,
    -- | The canonical type that the argument is narrowed to.
    _giNarrowType :: !Type
  }
  deriving (Eq, Show)

-- DECLARATIONS

-- | A linked list of top-level declarations in a module.
--
-- Declarations form a chain terminated by 'SaveTheEnvironment'.
-- Non-recursive definitions use 'Declare'; mutually recursive
-- groups use 'DeclareRec'.
data Decls
  = Declare Def Decls
  | DeclareRec Def [Def] Decls
  | -- | Sentinel value marking the end of a declaration chain.
    -- Named for historical reasons (inherited from Elm).
    SaveTheEnvironment
  deriving (Show)

-- PATTERNS

type Pattern =
  Ann.Located Pattern_

data Pattern_
  = PAnything
  | PVar Name
  | PRecord [Name]
  | PAlias Pattern Name
  | PUnit
  | PTuple Pattern Pattern (Maybe Pattern)
  | PList [Pattern]
  | PCons Pattern Pattern
  | PBool Union Bool
  | PChr ES.String
  | PStr ES.String
  | PInt Int
  | PCtor
      { _p_home :: ModuleName.Canonical,
        _p_type :: Name,
        _p_union :: Union,
        _p_name :: Name,
        _p_index :: Index.ZeroBased,
        _p_args :: [PatternCtorArg]
      }
  -- CACHE _p_home, _p_type, and _p_vars for type inference
  -- CACHE _p_index to replace _p_name in PROD code gen
  -- CACHE _p_opts to allocate less in PROD code gen
  -- CACHE _p_alts and _p_numAlts for exhaustiveness checker
  deriving (Show)

data PatternCtorArg = PatternCtorArg
  { _index :: Index.ZeroBased, -- CACHE for destructors/errors
    _type :: Type, -- CACHE for type inference
    _arg :: Pattern
  }
  deriving (Show)

-- TYPES

data Annotation = Forall FreeVars Type
  deriving (Eq, Show)

-- | Free type variables in scope. Uses @Map Name ()@ instead of @Set Name@
-- for compatibility with existing Map-based operations in the canonicalizer
-- and type solver, which frequently merge variable maps via 'Map.union'.
type FreeVars = Map Name ()

data Type
  = TLambda Type Type
  | TVar Name
  | TType ModuleName.Canonical Name [Type]
  | TRecord (Map Name FieldType) (Maybe Name)
  | TUnit
  | TTuple Type Type (Maybe Type)
  | TAlias ModuleName.Canonical Name [(Name, Type)] AliasType
  deriving (Eq, Show)

data AliasType
  = Holey Type
  | Filled Type
  deriving (Eq, Show)

data FieldType = FieldType {-# UNPACK #-} !Word16 Type
  deriving (Eq, Show)

-- NOTE: The Word16 marks the source order, but it may not be available
-- for every canonical type. For example, if the canonical type is inferred
-- the orders will all be zeros.
--
fieldsToList :: Map Name FieldType -> [(Name, Type)]
fieldsToList fields =
  fmap dropIndex (List.sortOn getIndex (Map.toList fields))
  where
    getIndex (_, FieldType index _) = index
    dropIndex (name, FieldType _ tipe) = (name, tipe)

-- MODULES

data Module = Module
  { _name :: ModuleName.Canonical,
    _exports :: Exports,
    _docs :: Src.Docs,
    _decls :: Decls,
    _unions :: Map Name Union,
    _aliases :: Map Name Alias,
    _binops :: Map Name Binop,
    _effects :: Effects,
    _lazyImports :: !(Set ModuleName.Canonical),
    -- | Type guard annotations for functions in this module.
    -- Maps function name to its guard info when the function
    -- is annotated with @guards@.
    _guards :: !(Map Name GuardInfo)
  }

-- | Supertype bound for opaque type aliases.
--
-- When a type alias is exported without its constructor (making it opaque),
-- a supertype bound declares which constrained operations the opaque type
-- supports externally.
--
-- @since 0.20.0
data SupertypeBound
  = ComparableBound
  | AppendableBound
  | NumberBound
  | CompAppendBound
  deriving (Eq, Show)

-- | Variance annotation for type parameters.
--
-- Controls how a type parameter can vary in the canonical representation.
-- Variance checking verifies that covariant parameters only appear in
-- positive (output) positions and contravariant parameters only appear
-- in negative (input) positions.
--
-- @since 0.20.0
data Variance
  = -- | Covariant (@+a@): output-only positions.
    Covariant
  | -- | Contravariant (@-a@): input-only positions.
    Contravariant
  | -- | Invariant (default): both input and output positions.
    Invariant
  deriving (Eq, Show)

-- | Deriving clause in canonical form.
--
-- @since 0.20.0
data DerivingClause
  = DeriveOrd
  | DeriveEncode !(Maybe JsonOptions)
  | DeriveDecode !(Maybe JsonOptions)
  | DeriveEnum
  deriving (Eq, Show)

-- | JSON options for deriving encoders/decoders.
--
-- @since 0.20.0
data JsonOptions = JsonOptions
  { _jsonFieldNaming :: !(Maybe NamingStrategy)
  , _jsonTagField :: !(Maybe Name)
  , _jsonContentsField :: !(Maybe Name)
  , _jsonOmitNothing :: !Bool
  , _jsonMissingAsNothing :: !Bool
  , _jsonUnwrapSingle :: !Bool
  }
  deriving (Eq, Show)

-- | Field naming strategy for JSON.
--
-- @since 0.20.0
data NamingStrategy
  = IdentityNaming
  | SnakeCase
  | CamelCase
  | KebabCase
  deriving (Eq, Show)

data Alias = Alias [Name] ![Variance] Type !(Maybe SupertypeBound) ![DerivingClause]
  deriving (Eq, Show)

data Binop = Binop_ Binop.Associativity Binop.Precedence Name
  deriving (Eq)

data Union = Union
  { _u_vars :: [Name],
    _u_variances :: ![Variance],
    _u_alts :: [Ctor],
    _u_numAlts :: Int, -- CACHE numAlts for exhaustiveness checking
    _u_opts :: CtorOpts, -- CACHE which optimizations are available
    _u_deriving :: ![DerivingClause]
  }
  deriving (Eq, Show)

data Ctor = Ctor Name Index.ZeroBased Int [Type] -- CACHE length args
  deriving (Eq, Show)

-- EXPORTS

data Exports
  = ExportEverything Ann.Region
  | Export (Map Name (Ann.Located Export))

-- | Individual export item type.
--
-- Represents the different kinds of items that can be exported
-- from a module with their specific export semantics.
--
-- @since 0.19.1
data Export
  = -- | Value or function export.
    --
    -- Exports a function or value definition.
    ExportValue
  | -- | Binary operator export.
    --
    -- Exports an infix operator definition.
    ExportBinop
  | -- | Type alias export.
    --
    -- Exports a type alias definition.
    ExportAlias
  | -- | Union type export with constructors.
    --
    -- Exports a union type with all its constructors visible.
    ExportUnionOpen
  | -- | Union type export without constructors.
    --
    -- Exports a union type but keeps constructors private.
    ExportUnionClosed
  | -- | Port export.
    --
    -- Exports a port for JavaScript interop.
    ExportPort

-- EFFECTS

data Effects
  = NoEffects
  | Ports (Map Name Port)
  | Manager Ann.Region Ann.Region Ann.Region Manager
  | FFI

data Port
  = Incoming {_freeVars :: FreeVars, _payload :: Type, _func :: Type}
  | Outgoing {_freeVars :: FreeVars, _payload :: Type, _func :: Type}

data Manager
  = Cmd Name
  | SubManager Name
  | Fx Name Name
