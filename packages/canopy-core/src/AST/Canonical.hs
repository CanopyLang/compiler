{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

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
    -- operators
    ArithOp (..),
    BinopKind (..),
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
    Manager (Cmd, SubManager, Fx),  -- Renamed SubManager to avoid collision with ArithOp.Sub
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
import qualified Reporting.InternalError as InternalError
import qualified Canopy.String as ES
import qualified Control.Monad as Monad
import qualified Data.Aeson as Aeson
import Data.Aeson.Types (Parser)
import qualified Data.Binary as Binary
import Data.Word (Word8, Word16)
import qualified Data.Foldable as Foldable
import qualified Data.Index as Index
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Name (Name)
import Data.Set (Set)
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
    -- * Int + Int → Int
    -- * Float + anything → Float
    -- * Int + Float → Float
    --
    -- Identity: x + 0 = 0 + x = x
    Add
  | -- | Subtraction operator (-).
    --
    -- Compiles to JavaScript '-' operator.
    --
    -- Semantics:
    -- * Int - Int → Int
    -- * Float - anything → Float
    -- * Int - Float → Float
    --
    -- Identity: x - 0 = x
    Sub
  | -- | Multiplication operator (*).
    --
    -- Compiles to JavaScript '*' operator.
    --
    -- Semantics:
    -- * Int * Int → Int
    -- * Float * anything → Float
    -- * Int * Float → Float
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
    -- * Int / Int → Float
    -- * Division by zero → Infinity or -Infinity
    --
    -- Identity: x / 1 = x
    -- Zero: 0 / x = 0 (for x ≠ 0)
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
  deriving (Show)

data CaseBranch
  = CaseBranch Pattern Expr
  deriving (Show)

data FieldUpdate
  = FieldUpdate Ann.Region Expr
  deriving (Show)

-- DEFS

data Def
  = Def (Ann.Located Name) [Pattern] Expr
  | TypedDef (Ann.Located Name) FreeVars [(Pattern, Type)] Expr Type
  deriving (Show)

-- DECLARATIONS

data Decls
  = Declare Def Decls
  | DeclareRec Def [Def] Decls
  | SaveTheEnvironment
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
    _effects :: Effects,
    _lazyImports :: !(Set ModuleName.Canonical)
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
  | SubManager Name  -- Renamed from Sub to avoid collision with ArithOp.Sub
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
  _ -> InternalError.report
    "AST.Canonical.putTypeComplex"
    "unexpected type in putTypeComplex"
    "putTypeComplex only handles TTuple, TAlias, and TType. Other type constructors (TLambda, TVar, TRecord, TUnit) must be serialized by their own Binary.put paths."

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

-- | Binary serialization for ArithOp.
--
-- Compact encoding using Word8 tags for efficient serialization.
--
-- @since 0.19.2
instance Binary.Binary ArithOp where
  put = putArithOp
  get = getArithOp

-- | Encode ArithOp to Word8.
--
-- Maps arithmetic operators to compact numeric tags.
--
-- @since 0.19.2
putArithOp :: ArithOp -> Binary.Put
putArithOp Add = Binary.putWord8 0
putArithOp Sub = Binary.putWord8 1
putArithOp Mul = Binary.putWord8 2
putArithOp Div = Binary.putWord8 3

-- | Decode Word8 to ArithOp.
--
-- Handles deserialization with error checking for corrupted data.
--
-- @since 0.19.2
getArithOp :: Binary.Get ArithOp
getArithOp = do
  w <- Binary.getWord8
  case w of
    0 -> pure Add
    1 -> pure Sub
    2 -> pure Mul
    3 -> pure Div
    _ -> fail ("binary encoding of ArithOp was corrupted: " ++ show w)

-- | Binary serialization for BinopKind.
--
-- Distinguishes native arithmetic from user-defined operators
-- with efficient tag-based encoding.
--
-- @since 0.19.2
instance Binary.Binary BinopKind where
  put kind = case kind of
    NativeArith op -> Binary.putWord8 0 >> Binary.put op
    UserDefined op home name ->
      Binary.putWord8 1 >> Binary.put op >> Binary.put home >> Binary.put name

  get = do
    tag <- Binary.getWord8
    case tag of
      0 -> fmap NativeArith Binary.get
      1 -> Monad.liftM3 UserDefined Binary.get Binary.get Binary.get
      _ -> fail ("binary encoding of BinopKind was corrupted: " ++ show tag)

-- AESON JSON INSTANCES

instance Aeson.ToJSON CtorOpts where
  toJSON opts = Aeson.String $
    case opts of
      Normal -> "normal"
      Enum -> "enum"
      Unbox -> "unbox"

instance Aeson.FromJSON CtorOpts where
  parseJSON = Aeson.withText "CtorOpts" $ \txt ->
    case txt of
      "normal" -> pure Normal
      "enum" -> pure Enum
      "unbox" -> pure Unbox
      _ -> fail ("Unknown CtorOpts: " ++ show txt)

instance Aeson.ToJSON Ctor where
  toJSON (Ctor name idx numArgs types) =
    Aeson.object
      [ "name" Aeson..= name,
        "index" Aeson..= idx,
        "numArgs" Aeson..= numArgs,
        "types" Aeson..= types
      ]

instance Aeson.FromJSON Ctor where
  parseJSON = Aeson.withObject "Ctor" $ \o ->
    Ctor
      <$> o Aeson..: "name"
      <*> o Aeson..: "index"
      <*> o Aeson..: "numArgs"
      <*> o Aeson..: "types"

instance Aeson.ToJSON Alias where
  toJSON (Alias vars tipe) =
    Aeson.object
      [ "vars" Aeson..= vars,
        "type" Aeson..= tipe
      ]

instance Aeson.FromJSON Alias where
  parseJSON = Aeson.withObject "Alias" $ \o ->
    Alias
      <$> o Aeson..: "vars"
      <*> o Aeson..: "type"

instance Aeson.ToJSON Union where
  toJSON (Union vars alts numAlts opts) =
    Aeson.object
      [ "vars" Aeson..= vars,
        "alts" Aeson..= alts,
        "numAlts" Aeson..= numAlts,
        "opts" Aeson..= opts
      ]

instance Aeson.FromJSON Union where
  parseJSON = Aeson.withObject "Union" $ \o ->
    Union
      <$> o Aeson..: "vars"
      <*> o Aeson..: "alts"
      <*> o Aeson..: "numAlts"
      <*> o Aeson..: "opts"

instance Aeson.ToJSON Annotation where
  toJSON (Forall freeVars tipe) =
    Aeson.object
      [ "freeVars" Aeson..= freeVars,
        "type" Aeson..= tipe
      ]

instance Aeson.FromJSON Annotation where
  parseJSON = Aeson.withObject "Annotation" $ \o ->
    Forall
      <$> o Aeson..: "freeVars"
      <*> o Aeson..: "type"

instance Aeson.ToJSON AliasType where
  toJSON aliasType = case aliasType of
    Holey tipe ->
      Aeson.object
        [ "tag" Aeson..= ("holey" :: String),
          "type" Aeson..= tipe
        ]
    Filled tipe ->
      Aeson.object
        [ "tag" Aeson..= ("filled" :: String),
          "type" Aeson..= tipe
        ]

instance Aeson.FromJSON AliasType where
  parseJSON = Aeson.withObject "AliasType" $ \o -> do
    tag <- o Aeson..: "tag" :: Parser String
    tipe <- o Aeson..: "type"
    case tag of
      "holey" -> pure (Holey tipe)
      "filled" -> pure (Filled tipe)
      _ -> fail ("Unknown AliasType tag: " ++ tag)

instance Aeson.ToJSON FieldType where
  toJSON (FieldType idx tipe) =
    Aeson.object
      [ "index" Aeson..= idx,
        "type" Aeson..= tipe
      ]

instance Aeson.FromJSON FieldType where
  parseJSON = Aeson.withObject "FieldType" $ \o ->
    FieldType
      <$> o Aeson..: "index"
      <*> o Aeson..: "type"

instance Aeson.ToJSON Type where
  toJSON tipe = case tipe of
    TLambda a b ->
      Aeson.object
        [ "tag" Aeson..= ("lambda" :: String),
          "arg" Aeson..= a,
          "result" Aeson..= b
        ]
    TVar name ->
      Aeson.object
        [ "tag" Aeson..= ("var" :: String),
          "name" Aeson..= name
        ]
    TType moduleName typeName args ->
      Aeson.object
        [ "tag" Aeson..= ("type" :: String),
          "module" Aeson..= moduleName,
          "name" Aeson..= typeName,
          "args" Aeson..= args
        ]
    TRecord fields ext ->
      Aeson.object
        [ "tag" Aeson..= ("record" :: String),
          "fields" Aeson..= fields,
          "extension" Aeson..= ext
        ]
    TUnit ->
      Aeson.object
        [ "tag" Aeson..= ("unit" :: String)
        ]
    TTuple a b c ->
      Aeson.object
        [ "tag" Aeson..= ("tuple" :: String),
          "first" Aeson..= a,
          "second" Aeson..= b,
          "third" Aeson..= c
        ]
    TAlias moduleName typeName args aliasType ->
      Aeson.object
        [ "tag" Aeson..= ("alias" :: String),
          "module" Aeson..= moduleName,
          "name" Aeson..= typeName,
          "args" Aeson..= args,
          "aliasType" Aeson..= aliasType
        ]

instance Aeson.FromJSON Type where
  parseJSON = Aeson.withObject "Type" $ \o -> do
    tag <- o Aeson..: "tag" :: Parser String
    case tag of
      "lambda" ->
        TLambda
          <$> o Aeson..: "arg"
          <*> o Aeson..: "result"
      "var" ->
        TVar <$> o Aeson..: "name"
      "type" ->
        TType
          <$> o Aeson..: "module"
          <*> o Aeson..: "name"
          <*> o Aeson..: "args"
      "record" ->
        TRecord
          <$> o Aeson..: "fields"
          <*> o Aeson..: "extension"
      "unit" ->
        pure TUnit
      "tuple" ->
        TTuple
          <$> o Aeson..: "first"
          <*> o Aeson..: "second"
          <*> o Aeson..: "third"
      "alias" ->
        TAlias
          <$> o Aeson..: "module"
          <*> o Aeson..: "name"
          <*> o Aeson..: "args"
          <*> o Aeson..: "aliasType"
      _ -> fail ("Unknown Type tag: " ++ tag)

