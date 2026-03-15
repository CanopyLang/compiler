{-# LANGUAGE StandaloneDeriving #-}

-- | The 'Expr' type for the Optimized AST.
--
-- This module defines the central 'Expr' data type used in the Canopy
-- Optimized AST. It is separated from "AST.Optimized" to keep each
-- module under the 800-line limit while avoiding circular imports.
--
-- The Optimized AST represents expressions in their final form before
-- code generation. All complex language constructs have been simplified
-- and optimized for direct translation to target languages.
--
-- @since 0.19.1
module AST.Optimized.Expr
  ( Expr (..),
    Global (..),
    Def (..),
    Destructor (..),
    Path (..),
    Decider (..),
    Choice (..),
  )
where

import qualified AST.Canonical as Can
import qualified AST.Utils.Shader as Shader
import qualified Canopy.Data.Index as Index
import Canopy.Data.Name (Name)
import qualified Canopy.Float as EF
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.String as ES
import qualified Control.Monad as Monad
import qualified Data.Binary as Binary
import Data.Map.Strict (Map)
import Data.Set (Set)
import Data.Word (Word8)
import qualified Optimize.DecisionTree as DT
import qualified Reporting.Annotation as Ann
import qualified Data.Text as Text
import qualified Reporting.InternalError as InternalError

-- EXPRESSIONS

-- | Optimized expression for efficient code generation.
--
-- Represents expressions in their final optimized form before code generation.
-- All complex language constructs have been simplified and optimized for
-- direct translation to target languages.
--
-- @since 0.19.1
data Expr
  = -- | Boolean literal.
    Bool Bool
  | -- | Character literal.
    Chr ES.String
  | -- | String literal.
    Str ES.String
  | -- | Integer literal.
    Int Int
  | -- | Floating point literal.
    Float EF.Float
  | -- | Local variable reference.
    --
    -- References to variables in the current scope (parameters, let-bindings).
    VarLocal Name
  | -- | Global variable reference.
    --
    -- References to global definitions with canonical module information.
    VarGlobal Global
  | -- | Enumeration constructor reference.
    --
    -- Optimized references to enum constructors that can be represented
    -- as integers. Index provides the efficient numeric representation.
    VarEnum Global Index.ZeroBased
  | -- | Boxed constructor reference.
    --
    -- References to constructors that require boxing for efficiency.
    VarBox Global
  | -- | Cyclic variable reference.
    --
    -- References to variables involved in recursive definitions.
    VarCycle ModuleName.Canonical Name
  | -- | Debug variable reference.
    --
    -- References to debug-only variables with source location information.
    VarDebug Name ModuleName.Canonical Ann.Region (Maybe Name)
  | -- | Runtime function reference.
    --
    -- Direct references to built-in runtime functions (e.g. @_Utils_eq@).
    VarRuntime Name Name
  | -- | List literal.
    List [Expr]
  | -- | Function definition.
    --
    -- Anonymous functions with parameter names and optimized body.
    Function [Name] Expr
  | -- | Function call.
    Call Expr [Expr]
  | -- | Native arithmetic binary operation.
    --
    -- Arithmetic operations after optimization passes. Compiles directly to
    -- JavaScript arithmetic operators in code generation.
    --
    -- @since 0.19.2
    ArithBinop !Can.ArithOp Expr Expr
  | -- | Tail call optimization.
    --
    -- Explicit tail calls that can be compiled to loops for efficiency.
    TailCall Name [(Name, Expr)]
  | -- | Conditional expression.
    If [(Expr, Expr)] Expr
  | -- | Let binding.
    Let Def Expr
  | -- | Destructuring assignment.
    Destruct Destructor Expr
  | -- | Optimized case expression.
    --
    -- Pattern matching compiled to efficient decision trees.
    Case Name Name (Decider Choice) [(Int, Expr)]
  | -- | Record field accessor function.
    Accessor Name
  | -- | Direct record field access.
    Access Expr Name
  | -- | Record update expression.
    Update Expr (Map Name Expr)
  | -- | Record literal.
    Record (Map Name Expr)
  | -- | Unit literal.
    Unit
  | -- | Tuple literal.
    Tuple Expr Expr (Maybe Expr)
  | -- | GLSL shader with dependency information.
    --
    -- Shader literals with computed dependency sets for efficient linking.
    Shader Shader.Source (Set Name) (Set Name)
  deriving (Show)

-- | Global variable reference with canonical module information.
--
-- @since 0.19.1
data Global = Global ModuleName.Canonical Name
  deriving (Show)

instance Eq Global where
  (==) (Global home1 name1) (Global home2 name2) =
    name1 == name2 && home1 == home2

instance Ord Global where
  compare (Global home1 name1) (Global home2 name2) =
    case compare name1 name2 of
      LT -> LT
      EQ -> compare home1 home2
      GT -> GT

-- DEFINITIONS

-- | Optimized definition forms.
--
-- @since 0.19.1
data Def
  = -- | Simple definition.
    Def Name Expr
  | -- | Tail-optimized definition.
    TailDef Name [Name] Expr
  deriving (Show)

-- | Destructuring specification for efficient field access.
--
-- @since 0.19.1
data Destructor
  = Destructor Name Path
  deriving (Show)

-- | Access path for destructuring operations.
--
-- @since 0.19.1
data Path
  = -- | Array/tuple index access.
    Index Index.ZeroBased Path
  | -- | Record field access.
    Field Name Path
  | -- | Unbox operation.
    Unbox Path
  | -- | Root variable.
    Root Name
  deriving (Show)

-- BRANCHING

-- | Decision tree for optimized pattern matching.
--
-- @since 0.19.1
data Decider a
  = -- | Leaf decision with final result.
    Leaf a
  | -- | Chain of tests with success/failure paths.
    Chain
      { _testChain :: [(DT.Path, DT.Test)],
        _success :: Decider a,
        _failure :: Decider a
      }
  | -- | Fan-out decision with multiple test branches.
    FanOut
      { _path :: DT.Path,
        _tests :: [(DT.Test, Decider a)],
        _fallback :: Decider a
      }
  deriving (Eq)

deriving instance Show a => Show (Decider a)

-- | Pattern matching choice specification.
--
-- @since 0.19.1
data Choice
  = -- | Inline expression directly.
    Inline Expr
  | -- | Jump to numbered branch.
    Jump Int
  deriving (Show)

-- BINARY INSTANCES

instance Binary.Binary Global where
  get = Monad.liftM2 Global Binary.get Binary.get
  put (Global a b) = Binary.put a >> Binary.put b

instance Binary.Binary Expr where
  put = putExpr
  get = getExpr

-- | Serialize an expression to binary format.
--
-- @since 0.19.1
putExpr :: Expr -> Binary.Put
putExpr expr = case expr of
  Bool a -> Binary.putWord8 0 >> Binary.put a
  Chr a -> Binary.putWord8 1 >> Binary.put a
  Str a -> Binary.putWord8 2 >> Binary.put a
  Int a -> Binary.putWord8 3 >> Binary.put a
  _ -> putExprComplex expr

-- | Serialize complex expressions to binary format.
--
-- @since 0.19.1
putExprComplex :: Expr -> Binary.Put
putExprComplex expr = case expr of
  Float a -> Binary.putWord8 4 >> Binary.put a
  VarLocal a -> Binary.putWord8 5 >> Binary.put a
  VarGlobal a -> Binary.putWord8 6 >> Binary.put a
  VarEnum a b -> Binary.putWord8 7 >> Binary.put a >> Binary.put b
  _ -> putExprVar expr

-- | Serialize variable expressions to binary format.
--
-- @since 0.19.1
putExprVar :: Expr -> Binary.Put
putExprVar expr = case expr of
  VarBox a -> Binary.putWord8 8 >> Binary.put a
  VarCycle a b -> Binary.putWord8 9 >> Binary.put a >> Binary.put b
  VarDebug a b c d -> Binary.putWord8 10 >> Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d
  VarRuntime a b -> Binary.putWord8 11 >> Binary.put a >> Binary.put b
  _ -> putExprControl expr

-- | Serialize control flow expressions to binary format.
--
-- @since 0.19.1
putExprControl :: Expr -> Binary.Put
putExprControl expr = case expr of
  List a -> Binary.putWord8 12 >> Binary.put a
  Function a b -> Binary.putWord8 13 >> Binary.put a >> Binary.put b
  Call a b -> Binary.putWord8 14 >> Binary.put a >> Binary.put b
  ArithBinop a b c -> Binary.putWord8 27 >> Binary.put a >> Binary.put b >> Binary.put c
  TailCall a b -> Binary.putWord8 15 >> Binary.put a >> Binary.put b
  _ -> putExprData expr

-- | Serialize data expressions to binary format.
--
-- @since 0.19.1
putExprData :: Expr -> Binary.Put
putExprData expr = case expr of
  If a b -> Binary.putWord8 16 >> Binary.put a >> Binary.put b
  Let a b -> Binary.putWord8 17 >> Binary.put a >> Binary.put b
  Destruct a b -> Binary.putWord8 18 >> Binary.put a >> Binary.put b
  Case a b c d -> Binary.putWord8 19 >> Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d
  _ -> putExprRecord expr

-- | Serialize record and tuple expressions to binary format.
--
-- @since 0.19.1
putExprRecord :: Expr -> Binary.Put
putExprRecord expr = case expr of
  Accessor a -> Binary.putWord8 20 >> Binary.put a
  Access a b -> Binary.putWord8 21 >> Binary.put a >> Binary.put b
  Update a b -> Binary.putWord8 22 >> Binary.put a >> Binary.put b
  Record a -> Binary.putWord8 23 >> Binary.put a
  Unit -> Binary.putWord8 24
  Tuple a b c -> Binary.putWord8 25 >> Binary.put a >> Binary.put b >> Binary.put c
  Shader a b c -> Binary.putWord8 26 >> Binary.put a >> Binary.put b >> Binary.put c
  Bool {} -> unexpectedExprInPutRecord "Bool"
  Chr {} -> unexpectedExprInPutRecord "Chr"
  Str {} -> unexpectedExprInPutRecord "Str"
  Int {} -> unexpectedExprInPutRecord "Int"
  Float {} -> unexpectedExprInPutRecord "Float"
  VarLocal {} -> unexpectedExprInPutRecord "VarLocal"
  VarGlobal {} -> unexpectedExprInPutRecord "VarGlobal"
  VarEnum {} -> unexpectedExprInPutRecord "VarEnum"
  VarBox {} -> unexpectedExprInPutRecord "VarBox"
  VarCycle {} -> unexpectedExprInPutRecord "VarCycle"
  VarDebug {} -> unexpectedExprInPutRecord "VarDebug"
  VarRuntime {} -> unexpectedExprInPutRecord "VarRuntime"
  List {} -> unexpectedExprInPutRecord "List"
  Function {} -> unexpectedExprInPutRecord "Function"
  Call {} -> unexpectedExprInPutRecord "Call"
  ArithBinop {} -> unexpectedExprInPutRecord "ArithBinop"
  TailCall {} -> unexpectedExprInPutRecord "TailCall"
  If {} -> unexpectedExprInPutRecord "If"
  Let {} -> unexpectedExprInPutRecord "Let"
  Destruct {} -> unexpectedExprInPutRecord "Destruct"
  Case {} -> unexpectedExprInPutRecord "Case"

-- | Report an unexpected expression reaching putExprRecord.
--
-- @since 0.19.2
unexpectedExprInPutRecord :: Text.Text -> a
unexpectedExprInPutRecord ctor =
  InternalError.report
    "AST.Optimized.Expr.putExprRecord"
    ("Unexpected expression `" <> ctor <> "` in putExprRecord")
    "putExprRecord only handles Accessor through Shader (tags 20-26). Other expression types must be serialized by the main putExpr dispatcher chain."

-- | Deserialize an expression from binary format.
--
-- @since 0.19.1
getExpr :: Binary.Get Expr
getExpr = do
  word <- Binary.getWord8
  case word of
    n | n <= 4 -> getExprSimple n
    n | n <= 11 -> getExprVar n
    n | n <= 19 -> getExprControl n
    n | n <= 26 -> getExprData n
    27 -> Monad.liftM3 ArithBinop Binary.get Binary.get Binary.get
    _ -> fail ("Opt.Expr: unexpected tag " ++ show word ++ " (expected 0-27). Delete canopy-stuff/ to rebuild.")

-- | Deserialize simple expressions (Bool, Chr, Str, Int, Float).
--
-- @since 0.19.1
getExprSimple :: Word8 -> Binary.Get Expr
getExprSimple word = case word of
  0 -> fmap Bool Binary.get
  1 -> fmap Chr Binary.get
  2 -> fmap Str Binary.get
  3 -> fmap Int Binary.get
  4 -> fmap Float Binary.get
  _ -> fail ("Opt.Expr.Simple: unexpected tag " ++ show word ++ " (expected 0-4). Delete canopy-stuff/ to rebuild.")

-- | Deserialize variable expressions.
--
-- @since 0.19.1
getExprVar :: Word8 -> Binary.Get Expr
getExprVar word = case word of
  5 -> fmap VarLocal Binary.get
  6 -> fmap VarGlobal Binary.get
  7 -> Monad.liftM2 VarEnum Binary.get Binary.get
  8 -> fmap VarBox Binary.get
  9 -> Monad.liftM2 VarCycle Binary.get Binary.get
  10 -> Monad.liftM4 VarDebug Binary.get Binary.get Binary.get Binary.get
  11 -> Monad.liftM2 VarRuntime Binary.get Binary.get
  _ -> fail ("Opt.Expr.Var: unexpected tag " ++ show word ++ " (expected 5-11). Delete canopy-stuff/ to rebuild.")

-- | Deserialize control flow expressions.
--
-- @since 0.19.1
getExprControl :: Word8 -> Binary.Get Expr
getExprControl word = case word of
  12 -> fmap List Binary.get
  13 -> Monad.liftM2 Function Binary.get Binary.get
  14 -> Monad.liftM2 Call Binary.get Binary.get
  15 -> Monad.liftM2 TailCall Binary.get Binary.get
  16 -> Monad.liftM2 If Binary.get Binary.get
  17 -> Monad.liftM2 Let Binary.get Binary.get
  18 -> Monad.liftM2 Destruct Binary.get Binary.get
  19 -> Monad.liftM4 Case Binary.get Binary.get Binary.get Binary.get
  _ -> fail ("Opt.Expr.Control: unexpected tag " ++ show word ++ " (expected 12-19). Delete canopy-stuff/ to rebuild.")

-- | Deserialize data structure expressions.
--
-- @since 0.19.1
getExprData :: Word8 -> Binary.Get Expr
getExprData word = case word of
  20 -> fmap Accessor Binary.get
  21 -> Monad.liftM2 Access Binary.get Binary.get
  22 -> Monad.liftM2 Update Binary.get Binary.get
  23 -> fmap Record Binary.get
  24 -> pure Unit
  25 -> Monad.liftM3 Tuple Binary.get Binary.get Binary.get
  26 -> Monad.liftM3 Shader Binary.get Binary.get Binary.get
  _ -> fail ("Opt.Expr.Data: unexpected tag " ++ show word ++ " (expected 20-26). Delete canopy-stuff/ to rebuild.")

instance Binary.Binary Def where
  put def =
    case def of
      Def a b -> Binary.putWord8 0 >> Binary.put a >> Binary.put b
      TailDef a b c -> Binary.putWord8 1 >> Binary.put a >> Binary.put b >> Binary.put c
  get = do
    word <- Binary.getWord8
    case word of
      0 -> Monad.liftM2 Def Binary.get Binary.get
      1 -> Monad.liftM3 TailDef Binary.get Binary.get Binary.get
      _ -> fail ("Opt.Def: unexpected tag " ++ show word ++ " (expected 0-1). Delete canopy-stuff/ to rebuild.")

instance Binary.Binary Destructor where
  get = Monad.liftM2 Destructor Binary.get Binary.get
  put (Destructor a b) = Binary.put a >> Binary.put b

instance Binary.Binary Path where
  put path =
    case path of
      Index a b -> Binary.putWord8 0 >> Binary.put a >> Binary.put b
      Field a b -> Binary.putWord8 1 >> Binary.put a >> Binary.put b
      Unbox a -> Binary.putWord8 2 >> Binary.put a
      Root a -> Binary.putWord8 3 >> Binary.put a
  get = do
    word <- Binary.getWord8
    case word of
      0 -> Monad.liftM2 Index Binary.get Binary.get
      1 -> Monad.liftM2 Field Binary.get Binary.get
      2 -> fmap Unbox Binary.get
      3 -> fmap Root Binary.get
      _ -> fail ("Opt.Path: unexpected tag " ++ show word ++ " (expected 0-3). Delete canopy-stuff/ to rebuild.")

instance (Binary.Binary a) => Binary.Binary (Decider a) where
  put decider =
    case decider of
      Leaf a -> Binary.putWord8 0 >> Binary.put a
      Chain a b c -> Binary.putWord8 1 >> Binary.put a >> Binary.put b >> Binary.put c
      FanOut a b c -> Binary.putWord8 2 >> Binary.put a >> Binary.put b >> Binary.put c
  get = do
    word <- Binary.getWord8
    case word of
      0 -> fmap Leaf Binary.get
      1 -> Monad.liftM3 Chain Binary.get Binary.get Binary.get
      2 -> Monad.liftM3 FanOut Binary.get Binary.get Binary.get
      _ -> fail ("Opt.Decider: unexpected tag " ++ show word ++ " (expected 0-2). Delete canopy-stuff/ to rebuild.")

instance Binary.Binary Choice where
  put choice =
    case choice of
      Inline expr -> Binary.putWord8 0 >> Binary.put expr
      Jump index -> Binary.putWord8 1 >> Binary.put index
  get = do
    word <- Binary.getWord8
    case word of
      0 -> fmap Inline Binary.get
      1 -> fmap Jump Binary.get
      _ -> fail ("Opt.Choice: unexpected tag " ++ show word ++ " (expected 0-1). Delete canopy-stuff/ to rebuild.")
