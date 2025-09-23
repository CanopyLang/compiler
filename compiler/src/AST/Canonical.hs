{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | AST.Canonical - Canonicalized AST after name resolution and type inference preparation
--
-- This module defines the Canonical AST representation used after the canonicalization
-- phase. Canonical AST differs from Source AST by having all names fully resolved to
-- their home modules, imports processed, and additional cached information for efficient
-- type inference and optimization.
--
-- The canonicalization process transforms the Source AST by:
-- * Resolving all qualified names to their canonical module homes
-- * Processing import declarations and exposing lists
-- * Caching metadata needed for later compiler phases
-- * Validating scoping and basic semantic constraints
--
-- == Key Features
--
-- * **Name Resolution** - All variables resolved to canonical module locations
-- * **Import Processing** - Imports resolved and scoping validated
-- * **Metadata Caching** - Performance data cached for later phases
-- * **Type Preparation** - AST prepared for efficient type inference
-- * **Optimization Ready** - Structure optimized for compiler transformations
--
-- == Architecture
--
-- The Canonical AST builds on Source AST with these enhancements:
--
-- * 'Expr' - Expressions with resolved names and cached type annotations
-- * 'Pattern' - Patterns with constructor metadata and exhaustiveness info
-- * 'Type' - Types with resolved names and alias expansion support
-- * 'Module' - Modules with processed imports and resolved exports
-- * 'Def' - Definitions with scope resolution and type preparation
--
-- Each construct includes caching annotations marked with "CACHE" comments
-- explaining what data is cached and why it improves performance.
--
-- == Caching Strategy
--
-- The Canonical AST aggressively caches information to avoid expensive lookups
-- in later compiler phases:
--
-- * **Type Information** - For efficient type inference (marked "CACHE for inference")
-- * **Constructor Data** - For exhaustiveness checking (marked "CACHE for exhaustiveness")
-- * **Optimization Hints** - For code generation (marked "CACHE for optimization")
-- * **Module Metadata** - For dependency analysis and linking
--
-- This caching strategy transforms O(log n) dictionary lookups into O(1) field access.
--
-- == Usage Examples
--
-- === Variable Resolution
--
-- @
-- -- Source AST: VarQual LowVar "List" "map" 
-- -- Canonical AST: VarForeign (Canonical Package.core "List") "map" annotation
--
-- -- Local variable remains: VarLocal "x"
-- -- Top-level becomes: VarTopLevel home "myFunction"
-- @
--
-- === Constructor Patterns
--
-- @
-- -- Canonical pattern with cached metadata
-- let maybePattern = PCtor
--   { _p_home = ModuleName.Canonical Package.core "Maybe"
--   , _p_type = "Maybe"
--   , _p_union = cachedUnionInfo  -- CACHE for exhaustiveness
--   , _p_name = "Just"
--   , _p_index = Index.first      -- CACHE for code generation
--   , _p_args = [PatternCtorArg Index.first typeInfo argPattern]
--   }
-- @
--
-- === Module Structure
--
-- @
-- -- Complete canonical module
-- let canonicalModule = Module
--   { _name = ModuleName.Canonical package "MyModule"
--   , _exports = processedExports
--   , _docs = preservedDocs
--   , _decls = optimizedDeclarations
--   , _unions = resolvedUnions
--   , _aliases = expandedAliases
--   , _binops = resolvedOperators
--   , _effects = processedEffects
--   }
-- @
--
-- == Error Handling
--
-- Canonical AST assumes successful canonicalization - any name resolution
-- or scoping errors should be caught during the canonicalization phase.
-- The canonical representation should be internally consistent.
--
-- == Performance Characteristics
--
-- * **Memory Usage**: Higher than Source AST due to cached metadata
-- * **Construction**: O(n * log m) where n = nodes, m = module scope size
-- * **Access**: O(1) for most cached lookups vs O(log n) dictionary access
-- * **Type Inference**: Significantly faster due to pre-cached type information
--
-- == Thread Safety
--
-- All Canonical AST types are immutable and thread-safe. The cached metadata
-- is computed during canonicalization and remains constant thereafter.
--
-- @since 0.19.1
module AST.Canonical
  ( Expr,
    Expr_ (..),
    CaseBranch (..),
    FieldUpdate (..),
    CtorOpts (..),
    -- definitions
    Def (..),
    Decls (..),
    -- patterns
    Pattern,
    Pattern_ (..),
    PatternCtorArg (..),
    -- types
    Annotation (..),
    Type (..),
    AliasType (..),
    FieldType (..),
    fieldsToList,
    -- modules
    Module (..),
    Alias (..),
    Binop (..),
    Union (..),
    Ctor (..),
    Exports (..),
    Export (..),
    Effects (..),
    Port (..),
    Manager (..),
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
import qualified Canopy.Float as EF
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.String as ES
import qualified Control.Monad as Monad
import qualified Data.Binary as Binary
import Data.Word (Word8, Word16)
import qualified Data.Foldable as Foldable
import qualified Data.Index as Index
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Name (Name)
import qualified Reporting.Annotation as A

-- EXPRESSIONS

type Expr =
  A.Located Expr_

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
  | Binop Name ModuleName.Canonical Name Annotation Expr Expr -- CACHE real name for optimization
  | Lambda [Pattern] Expr
  | Call Expr [Expr]
  | If [(Expr, Expr)] Expr
  | Let Def Expr
  | LetRec [Def] Expr
  | LetDestruct Pattern Expr Expr
  | Case Expr [CaseBranch]
  | Accessor Name
  | Access Expr (A.Located Name)
  | Update Name Expr (Map Name FieldUpdate)
  | Record (Map Name Expr)
  | Unit
  | Tuple Expr Expr (Maybe Expr)
  | Shader Shader.Source Shader.Types
  deriving (Show)

data CaseBranch
  = CaseBranch Pattern Expr
  deriving (Show)

data FieldUpdate
  = FieldUpdate A.Region Expr
  deriving (Show)

-- DEFS

data Def
  = Def (A.Located Name) [Pattern] Expr
  | TypedDef (A.Located Name) FreeVars [(Pattern, Type)] Expr Type
  deriving (Show)

-- DECLARATIONS

data Decls
  = Declare Def Decls
  | DeclareRec Def [Def] Decls
  | SaveTheEnvironment
  deriving (Show)

-- PATTERNS

type Pattern =
  A.Located Pattern_

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
  let getIndex (_, FieldType index _) =
        index

      dropIndex (name, FieldType _ tipe) =
        (name, tipe)
   in fmap dropIndex (List.sortOn getIndex (Map.toList fields))

-- MODULES

data Module = Module
  { _name :: ModuleName.Canonical,
    _exports :: Exports,
    _docs :: Src.Docs,
    _decls :: Decls,
    _unions :: Map Name Union,
    _aliases :: Map Name Alias,
    _binops :: Map Name Binop,
    _effects :: Effects
  }

data Alias = Alias [Name] Type
  deriving (Eq, Show)

data Binop = Binop_ Binop.Associativity Binop.Precedence Name
  deriving (Eq)

data Union = Union
  { _u_vars :: [Name],
    _u_alts :: [Ctor],
    _u_numAlts :: Int, -- CACHE numAlts for exhaustiveness checking
    _u_opts :: CtorOpts -- CACHE which optimizations are available
  }
  deriving (Eq, Show)

data CtorOpts
  = Normal
  | Enum
  | Unbox
  deriving (Eq, Ord, Show)

data Ctor = Ctor Name Index.ZeroBased Int [Type] -- CACHE length args
  deriving (Eq, Show)

-- EXPORTS

data Exports
  = ExportEverything A.Region
  | Export (Map Name (A.Located Export))

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
  | Manager A.Region A.Region A.Region Manager
  | FFI

data Port
  = Incoming {_freeVars :: FreeVars, _payload :: Type, _func :: Type}
  | Outgoing {_freeVars :: FreeVars, _payload :: Type, _func :: Type}

data Manager
  = Cmd Name
  | Sub Name
  | Fx Name Name

-- BINARY

instance Binary.Binary Alias where
  get = Monad.liftM2 Alias Binary.get Binary.get
  put (Alias a b) = Binary.put a >> Binary.put b  -- Note: Alias is a constructor, not a record

instance Binary.Binary Union where
  put (Union a b c d) = Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d
  get = Monad.liftM4 Union Binary.get Binary.get Binary.get Binary.get

instance Binary.Binary Ctor where
  get = Monad.liftM4 Ctor Binary.get Binary.get Binary.get Binary.get
  put (Ctor a b c d) = Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d  -- Note: Ctor is a constructor, not a record

instance Binary.Binary CtorOpts where
  put opts =
    case opts of
      Normal -> Binary.putWord8 0
      Enum -> Binary.putWord8 1
      Unbox -> Binary.putWord8 2

  get =
    do
      n <- Binary.getWord8
      case n of
        0 -> return Normal
        1 -> return Enum
        2 -> return Unbox
        _ -> fail "binary encoding of CtorOpts was corrupted"

instance Binary.Binary Annotation where
  get = Monad.liftM2 Forall Binary.get Binary.get
  put (Forall a b) = Binary.put a >> Binary.put b  -- Note: Forall is a constructor, not a record

instance Binary.Binary Type where
  put = putType
  get = getType

-- | Serialize a type to binary format.
--
-- Efficiently serializes canonical types to binary representation for
-- module interface files and compilation caching.
--
-- @since 0.19.1
putType :: Type -> Binary.Put
putType tipe = case tipe of
  TLambda a b -> Binary.putWord8 0 >> Binary.put a >> Binary.put b
  TVar a -> Binary.putWord8 1 >> Binary.put a
  TRecord a b -> Binary.putWord8 2 >> Binary.put a >> Binary.put b
  TUnit -> Binary.putWord8 3
  _ -> putTypeComplex tipe

-- | Serialize complex types to binary format.
--
-- Handles serialization of complex type constructs like tuples,
-- aliases, and parameterized types.
--
-- @since 0.19.1
putTypeComplex :: Type -> Binary.Put
putTypeComplex tipe = case tipe of
  TTuple a b c -> Binary.putWord8 4 >> Binary.put a >> Binary.put b >> Binary.put c
  TAlias a b c d -> Binary.putWord8 5 >> Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d
  TType home name ts -> putTType home name ts
  _ -> error "putTypeComplex: unexpected type"

-- | Serialize TType with optimization for small type lists.
--
-- Uses an optimization for type applications with few arguments
-- to reduce serialization overhead in common cases.
--
-- @since 0.19.1
putTType :: ModuleName.Canonical -> Name -> [Type] -> Binary.Put
putTType home name ts =
  let potentialWord = length ts + 7
   in if potentialWord <= fromIntegral (maxBound :: Word8)
        then do
          Binary.putWord8 (fromIntegral potentialWord)
          Binary.put home
          Binary.put name
          Foldable.traverse_ Binary.put ts
        else Binary.putWord8 6 >> Binary.put home >> Binary.put name >> Binary.put ts

-- | Deserialize a type from binary format.
--
-- Efficiently deserializes canonical types from binary representation
-- with proper error handling for corrupted data.
--
-- @since 0.19.1
getType :: Binary.Get Type
getType = do
  word <- Binary.getWord8
  case word of
    n | n <= 5 -> getTypeSimple n
    6 -> Monad.liftM3 TType Binary.get Binary.get Binary.get
    n -> getTTypeOptimized n

-- | Deserialize simple types.
--
-- Handles deserialization of basic type constructs like functions,
-- variables, records, and units.
--
-- @since 0.19.1
getTypeSimple :: Word8 -> Binary.Get Type
getTypeSimple word = case word of
  0 -> Monad.liftM2 TLambda Binary.get Binary.get
  1 -> fmap TVar Binary.get
  2 -> Monad.liftM2 TRecord Binary.get Binary.get
  3 -> return TUnit
  4 -> Monad.liftM3 TTuple Binary.get Binary.get Binary.get
  5 -> Monad.liftM4 TAlias Binary.get Binary.get Binary.get Binary.get
  _ -> fail "getTypeSimple: unexpected word"

-- | Deserialize TType with optimized length encoding.
--
-- Handles the optimized encoding for type applications with
-- length information encoded in the tag byte.
--
-- @since 0.19.1
getTTypeOptimized :: Word8 -> Binary.Get Type
getTTypeOptimized n =
  Monad.liftM3 TType Binary.get Binary.get (Monad.replicateM (fromIntegral (n - 7)) Binary.get)

instance Binary.Binary AliasType where
  put aliasType =
    case aliasType of
      Holey tipe -> Binary.putWord8 0 >> Binary.put tipe
      Filled tipe -> Binary.putWord8 1 >> Binary.put tipe

  get =
    do
      n <- Binary.getWord8
      case n of
        0 -> fmap Holey Binary.get
        1 -> fmap Filled Binary.get
        _ -> fail "binary encoding of AliasType was corrupted"

instance Binary.Binary FieldType where
  get = Monad.liftM2 FieldType Binary.get Binary.get
  put (FieldType a b) = Binary.put a >> Binary.put b  -- Note: FieldType is a constructor, not a record

