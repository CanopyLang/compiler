{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | AST.Optimized - Optimized AST for efficient code generation
--
-- This module defines the Optimized AST representation used after optimization
-- passes and before final code generation. The Optimized AST is designed for
-- maximum efficiency in code generation with simplified constructs, resolved
-- dependencies, and optimized control flow.
--
-- The optimization process transforms the Canonical AST by:
-- * Simplifying expression forms for efficient codegen
-- * Resolving all variable references to global/local classification
-- * Optimizing pattern matching with decision trees
-- * Flattening nested scopes and optimizing function calls
-- * Building dependency graphs for dead code elimination
--
-- == Key Features
--
-- * **Simplified Expressions** - Minimal expression forms optimized for codegen
-- * **Global Variables** - All references resolved to global or local classification
-- * **Decision Trees** - Pattern matching optimized with decision tree compilation
-- * **Dependency Graphs** - Complete dependency tracking for optimization
-- * **Tail Call Optimization** - Explicit tail call representation
-- * **Kernel Integration** - Direct support for kernel function calls
--
-- == Architecture
--
-- The Optimized AST represents the final form before code generation:
--
-- * 'Expr' - Simplified expressions with efficient representations
-- * 'Global' - Global variable references with canonical module information
-- * 'Def' - Optimized definitions with tail call forms
-- * 'Decider' - Decision trees for efficient pattern matching compilation
-- * 'GlobalGraph' - Complete dependency graphs for linking and optimization
--
-- Each construct is designed for direct translation to target languages
-- with minimal additional processing required.
--
-- == Optimization Strategy
--
-- The Optimized AST incorporates several key optimizations:
--
-- * **Variable Classification** - Efficient local vs global access patterns
-- * **Pattern Compilation** - Decision trees minimize runtime pattern testing
-- * **Tail Call Optimization** - Explicit tail calls avoid stack growth
-- * **Dead Code Elimination** - Dependency graphs enable precise DCE
-- * **Constructor Optimization** - Efficient representations for enums and unboxing
--
-- == Usage Examples
--
-- === Global Variable References
--
-- @
-- -- Local variable (function parameter)
-- let localVar = VarLocal "x"
--
-- -- Global function from same module
-- let globalVar = VarGlobal (Global currentModule "helper")
--
-- -- Kernel function
-- let kernelVar = VarKernel "eq" "$eq"
-- @
--
-- === Optimized Function Definitions
--
-- @
-- -- Simple definition
-- let simpleDef = Def "square" (Call (VarLocal "x") [VarLocal "x"])
--
-- -- Tail-optimized recursive function
-- let tailDef = TailDef "factorial" ["n", "acc"] 
--   (TailCall "factorial" [("n", Call subtract [VarLocal "n", Int 1]),
--                         ("acc", Call multiply [VarLocal "n", VarLocal "acc"])])
-- @
--
-- === Decision Tree Pattern Matching
--
-- @
-- -- Optimized case expression with decision tree
-- let optimizedCase = Case "input" "result" decisionTree
--   [(0, Str "nothing"),    -- Nothing branch
--    (1, VarLocal "value")] -- Just branch
-- @
--
-- === Dependency Graph Construction
--
-- @
-- -- Build global dependency graph
-- let graph = addGlobalGraph moduleGraph1 moduleGraph2
-- let finalGraph = addKernel "customOp" kernelChunks graph
-- @
--
-- == Error Handling
--
-- The Optimized AST assumes successful optimization - any optimization
-- failures should be caught during the optimization phases. The optimized
-- representation should be ready for direct code generation.
--
-- == Performance Characteristics
--
-- * **Memory Usage**: Optimized for minimal allocation during codegen
-- * **Code Generation**: Direct translation with minimal processing overhead
-- * **Pattern Matching**: O(log n) pattern tests via decision trees
-- * **Variable Access**: O(1) local access, O(1) global lookup
-- * **Dependency Analysis**: Pre-computed graphs enable fast analysis
--
-- == Thread Safety
--
-- All Optimized AST types are immutable and thread-safe. Code generation
-- can be parallelized across modules using the dependency graph information.
--
-- @since 0.19.1
module AST.Optimized
  ( Def (..),
    Expr (..),
    Global (..),
    Path (..),
    Destructor (..),
    Decider (..),
    Choice (..),
    GlobalGraph (..),
    LocalGraph (..),
    Main (..),
    Node (..),
    EffectsType (..),
    empty,
    addGlobalGraph,
    addLocalGraph,
    addKernel,
    toKernelGlobal,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Utils.Shader as Shader
import qualified Canopy.Float as EF
import qualified Canopy.Kernel as K
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Reporting.InternalError as InternalError
import qualified Canopy.String as ES
import Control.Applicative ((<|>))
import qualified Control.Monad as Monad
import qualified Data.Binary as Binary
import Data.Word (Word8)
import qualified Data.Index as Index
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Name (Name)
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Optimize.DecisionTree as DT
import qualified Reporting.Annotation as A

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
    --
    -- Direct boolean values for efficient comparison and branching.
    Bool Bool
  | -- | Character literal.
    --
    -- Character literals exactly as in earlier AST forms.
    Chr ES.String
  | -- | String literal.
    --
    -- String literals exactly as in earlier AST forms.
    Str ES.String
  | -- | Integer literal.
    --
    -- Integer literals exactly as in earlier AST forms.
    Int Int
  | -- | Floating point literal.
    --
    -- Float literals exactly as in earlier AST forms.
    Float EF.Float
  | -- | Local variable reference.
    --
    -- References to variables in the current scope (parameters, let-bindings).
    -- Optimized for efficient local variable access in generated code.
    VarLocal Name
  | -- | Global variable reference.
    --
    -- References to global definitions with canonical module information.
    -- Enables efficient cross-module function calls and constant access.
    VarGlobal Global
  | -- | Enumeration constructor reference.
    --
    -- Optimized references to enum constructors that can be represented
    -- as integers. Index provides the efficient numeric representation.
    VarEnum Global Index.ZeroBased
  | -- | Boxed constructor reference.
    --
    -- References to constructors that require boxing for efficiency.
    -- Used for single-constructor types that can avoid tagging overhead.
    VarBox Global
  | -- | Cyclic variable reference.
    --
    -- References to variables involved in recursive definitions.
    -- Requires special handling for proper initialization order.
    VarCycle ModuleName.Canonical Name
  | -- | Debug variable reference.
    --
    -- References to debug-only variables with source location information.
    -- Includes original name for debugging and error reporting.
    VarDebug Name ModuleName.Canonical A.Region (Maybe Name)
  | -- | Kernel function reference.
    --
    -- Direct references to built-in kernel functions for maximum efficiency.
    -- First name is the high-level name, second is the runtime implementation.
    VarKernel Name Name
  | -- | List literal.
    --
    -- List literals with optimized element expressions.
    List [Expr]
  | -- | Function definition.
    --
    -- Anonymous functions with parameter names and optimized body.
    -- Parameters are guaranteed to be simple names for efficient binding.
    Function [Name] Expr
  | -- | Function call.
    --
    -- Function calls with optimized function and argument expressions.
    Call Expr [Expr]
  | -- | Native arithmetic binary operation.
    --
    -- Arithmetic operations after optimization passes. May have had constant
    -- folding, identity elimination, or absorption applied during optimization.
    --
    -- Generated by 'Optimize.Expression.optimize' when processing 'Can.BinopOp'
    -- nodes with 'NativeArith' classification. Compiles directly to JavaScript
    -- arithmetic operators in code generation for maximum performance.
    --
    -- Supports:
    -- * Add (+) - JavaScript '+' operator
    -- * Sub (-) - JavaScript '-' operator
    -- * Mul (*) - JavaScript '*' operator
    -- * Div (/) - JavaScript '/' operator
    --
    -- @since 0.19.2
    ArithBinop !Can.ArithOp Expr Expr
  | -- | Tail call optimization.
    --
    -- Explicit tail calls that can be compiled to loops for efficiency.
    -- Function name and argument bindings enable direct loop compilation.
    TailCall Name [(Name, Expr)]
  | -- | Conditional expression.
    --
    -- Optimized conditionals with efficient branching structure.
    If [(Expr, Expr)] Expr
  | -- | Let binding.
    --
    -- Single let bindings with optimized definitions.
    Let Def Expr
  | -- | Destructuring assignment.
    --
    -- Optimized destructuring with efficient field access patterns.
    Destruct Destructor Expr
  | -- | Optimized case expression.
    --
    -- Pattern matching compiled to efficient decision trees.
    -- Names are the input and result variables, Decider is the compiled tree.
    Case Name Name (Decider Choice) [(Int, Expr)]
  | -- | Record field accessor function.
    --
    -- Efficient field accessor generation for record field access.
    Accessor Name
  | -- | Direct record field access.
    --
    -- Optimized record field access with resolved field names.
    Access Expr Name
  | -- | Record update expression.
    --
    -- Efficient record updates with field mapping optimization.
    Update Expr (Map Name Expr)
  | -- | Record literal.
    --
    -- Optimized record construction with efficient field mapping.
    Record (Map Name Expr)
  | -- | Unit literal.
    --
    -- Unit values exactly as in earlier AST forms.
    Unit
  | -- | Tuple literal.
    --
    -- Optimized tuple construction with efficient component access.
    Tuple Expr Expr (Maybe Expr)
  | -- | GLSL shader with dependency information.
    --
    -- Shader literals with computed dependency sets for efficient linking.
    -- Dependency sets enable proper module ordering and dead code elimination.
    Shader Shader.Source (Set Name) (Set Name)
  deriving (Show)

-- | Global variable reference with canonical module information.
--
-- Represents references to global definitions with their canonical module
-- location. Used throughout the optimized AST for efficient cross-module
-- references and dependency tracking.
--
-- @since 0.19.1
data Global = Global ModuleName.Canonical Name
  deriving (Show)

-- DEFINITIONS

-- | Optimized definition forms.
--
-- Represents function and value definitions in their optimized form
-- with support for tail call optimization and efficient compilation.
--
-- @since 0.19.1
data Def
  = -- | Simple definition.
    --
    -- Basic function or value definition with optimized expression.
    Def Name Expr
  | -- | Tail-optimized definition.
    --
    -- Function definition optimized for tail recursion with explicit
    -- parameter list and tail-optimized body expression.
    TailDef Name [Name] Expr
  deriving (Show)

-- | Destructuring specification for efficient field access.
--
-- Represents how to destructure values with optimized access paths
-- for efficient code generation.
--
-- @since 0.19.1
data Destructor
  = Destructor Name Path
  deriving (Show)

-- | Access path for destructuring operations.
--
-- Represents the path taken to access nested values in data structures.
-- Optimized for efficient field access and tuple indexing in generated code.
--
-- @since 0.19.1
data Path
  = -- | Array/tuple index access.
    --
    -- Accesses the element at the specified zero-based index.
    Index Index.ZeroBased Path
  | -- | Record field access.
    --
    -- Accesses the named field in a record structure.
    Field Name Path
  | -- | Unbox operation.
    --
    -- Removes boxing from single-constructor types for efficiency.
    Unbox Path
  | -- | Root variable.
    --
    -- The base variable being destructured.
    Root Name
  deriving (Show)

-- BRANCHING

-- | Decision tree for optimized pattern matching.
--
-- Represents compiled pattern matching as efficient decision trees
-- that minimize the number of runtime tests needed to determine
-- which pattern matches.
--
-- @since 0.19.1
data Decider a
  = -- | Leaf decision with final result.
    --
    -- Represents the end of a decision path with the final result.
    Leaf a
  | -- | Chain of tests with success/failure paths.
    --
    -- Represents a sequence of tests that must all succeed to reach
    -- the success branch, otherwise takes the failure branch.
    Chain
      { -- | Sequence of tests to perform
        _testChain :: [(DT.Path, DT.Test)],
        -- | Decision tree for when all tests succeed
        _success :: Decider a,
        -- | Decision tree for when any test fails
        _failure :: Decider a
      }
  | -- | Fan-out decision with multiple test branches.
    --
    -- Represents a decision point that tests a value and branches
    -- to different sub-trees based on the test results.
    FanOut
      { -- | Path to the value being tested
        _path :: DT.Path,
        -- | Test cases and their corresponding decision trees
        _tests :: [(DT.Test, Decider a)],
        -- | Fallback decision tree when no tests match
        _fallback :: Decider a
      }
  deriving (Eq)

deriving instance Show a => Show (Decider a)

-- | Pattern matching choice specification.
--
-- Represents the action to take when a pattern matches, either
-- inlining an expression or jumping to a pre-computed branch.
--
-- @since 0.19.1
data Choice
  = -- | Inline expression directly.
    --
    -- Generates the expression inline at the match site for efficiency.
    Inline Expr
  | -- | Jump to numbered branch.
    --
    -- Jumps to a pre-computed branch identified by integer index.
    -- Enables efficient compilation of complex pattern matching.
    Jump Int
  deriving (Show)

-- OBJECT GRAPH

-- | Global dependency graph for modules.
--
-- Represents the complete dependency graph across all modules in a program.
-- Used for link-time optimization, dead code elimination, and efficient
-- code generation ordering.
--
-- @since 0.19.1
data GlobalGraph = GlobalGraph
  { -- | Mapping from global names to their definitions
    _g_nodes :: Map Global Node,
    -- | Field usage counts for optimization
    _g_fields :: Map Name Int,
    -- | Source locations for each global, used for source map generation
    _g_sourceLocations :: Map Global A.Region
  }
  deriving (Show)

-- | Local dependency graph for a single module.
--
-- Represents the dependency graph within a single module, including
-- the main function information and local dependencies.
--
-- @since 0.19.1
data LocalGraph = LocalGraph
  { -- | Main function specification if present
    _l_main :: Maybe Main,
    -- | Local node definitions
    -- PERF: Consider switching Global to Name for better performance
    _l_nodes :: Map Global Node,
    -- | Field usage counts for optimization
    _l_fields :: Map Name Int,
    -- | Source locations for each global, used for source map generation
    _l_sourceLocations :: Map Global A.Region
  }
  deriving (Show)

-- | Main function specification for applications.
--
-- Represents the main entry point for Canopy applications with
-- support for both static and dynamic (message-based) applications.
--
-- @since 0.19.1
data Main
  = -- | Static application without runtime messages.
    --
    -- Represents applications that don't use the Elm Architecture
    -- and have a simple static main function (e.g. @main : Html msg@).
    Static
  | -- | Dynamic application with message handling.
    --
    -- Represents applications using the Elm Architecture with
    -- message types and JSON decoders for initialization.
    Dynamic
      { -- | Message type for the application
        _message :: Can.Type,
        -- | JSON decoder for initialization flags
        _decoder :: Expr
      }
  | -- | Test or non-visual main that should be exported as a raw value.
    --
    -- The main value is exported directly without wrapping in
    -- @_VirtualDom_init@, allowing test harnesses to access the
    -- data structure and execute it with the appropriate runner.
    TestMain
  deriving (Show)

-- | Dependency graph node representing definitions.
--
-- Represents different kinds of definitions in the dependency graph
-- with their associated metadata and dependencies.
--
-- @since 0.19.1
data Node
  = -- | Simple definition with dependencies.
    --
    -- Regular function or value definition with its expression and
    -- the set of global definitions it depends on.
    Define Expr (Set Global)
  | -- | Tail-optimized function definition.
    --
    -- Function definition optimized for tail calls with parameter
    -- names, body expression, and dependencies.
    DefineTailFunc [Name] Expr (Set Global)
  | -- | Constructor definition.
    --
    -- Type constructor with its index and arity for efficient
    -- code generation and runtime representation.
    Ctor Index.ZeroBased Int
  | -- | Enumeration constructor.
    --
    -- Constructor for enumeration types that can be represented
    -- as simple integers for maximum efficiency.
    Enum Index.ZeroBased
  | -- | Boxed constructor.
    --
    -- Constructor that requires boxing for single-constructor types
    -- to avoid unnecessary runtime tagging overhead.
    Box
  | -- | Link to another global definition.
    --
    -- Represents aliases and references to other global definitions
    -- for efficient indirection and optimization.
    Link Global
  | -- | Recursive definition cycle.
    --
    -- Represents mutually recursive definitions that need special
    -- handling for proper initialization and optimization.
    Cycle [Name] [(Name, Expr)] [Def] (Set Global)
  | -- | Effect manager definition.
    --
    -- Represents effect managers for handling side effects
    -- with their specific effect type classification.
    Manager EffectsType
  | -- | Kernel function definition.
    --
    -- Built-in kernel functions with their implementation chunks
    -- and dependencies for efficient runtime integration.
    Kernel [K.Chunk] (Set Global)
  | -- | Incoming port definition.
    --
    -- JavaScript-to-Canopy port with decoder expression and dependencies.
    PortIncoming Expr (Set Global)
  | -- | Outgoing port definition.
    --
    -- Canopy-to-JavaScript port with encoder expression and dependencies.
    PortOutgoing Expr (Set Global)
  deriving (Show)

-- | Effect type classification for effect managers.
--
-- Represents the different kinds of effects that can be managed
-- by effect managers in the Canopy runtime.
--
-- @since 0.19.1
data EffectsType 
  = -- | Command effects.
    --
    -- Effects that represent commands to be executed by the runtime.
    Cmd 
  | -- | Subscription effects.
    --
    -- Effects that represent subscriptions to external events.
    Sub 
  | -- | Combined command and subscription effects.
    --
    -- Effects that can both send commands and receive subscriptions.
    Fx
  deriving (Show)

-- GRAPHS

-- | Create an empty global dependency graph.
--
-- Creates a new empty global graph with no nodes or field information.
-- Used as the starting point for building dependency graphs.
--
-- @since 0.19.1
{-# NOINLINE empty #-}
empty :: GlobalGraph
empty =
  GlobalGraph Map.empty Map.empty Map.empty

-- | Combine two global dependency graphs.
--
-- Merges two global graphs by taking the union of their nodes and fields.
-- Used to combine dependency information from multiple modules.
--
-- @since 0.19.1
addGlobalGraph :: GlobalGraph -> GlobalGraph -> GlobalGraph
addGlobalGraph (GlobalGraph nodes1 fields1 locs1) (GlobalGraph nodes2 fields2 locs2) =
  GlobalGraph
    { _g_nodes = Map.union nodes1 nodes2,
      _g_fields = Map.union fields1 fields2,
      _g_sourceLocations = Map.union locs1 locs2
    }

-- | Add local graph information to global graph.
--
-- Incorporates a module's local dependency graph into the global graph
-- by merging nodes and field information. Main function info is discarded
-- as it's only relevant within the local module.
--
-- @since 0.19.1
addLocalGraph :: LocalGraph -> GlobalGraph -> GlobalGraph
addLocalGraph (LocalGraph _ nodes1 fields1 locs1) (GlobalGraph nodes2 fields2 locs2) =
  GlobalGraph
    { _g_nodes = Map.union nodes1 nodes2,
      _g_fields = Map.union fields1 fields2,
      _g_sourceLocations = Map.union locs1 locs2
    }

-- | Add kernel function to global dependency graph.
--
-- Registers a kernel function in the global graph with its implementation
-- chunks and computed dependencies. Kernel functions are built-in runtime
-- functions that provide core language functionality.
--
-- @since 0.19.1
addKernel :: Name.Name -> [K.Chunk] -> GlobalGraph -> GlobalGraph
addKernel shortName chunks (GlobalGraph nodes fields locs) =
  let global = toKernelGlobal shortName
      node = Kernel chunks (foldr addKernelDep Set.empty chunks)
   in GlobalGraph
        { _g_nodes = Map.insert global node nodes,
          _g_fields = Map.union (K.countFields chunks) fields,
          _g_sourceLocations = locs
        }

addKernelDep :: K.Chunk -> Set Global -> Set Global
addKernelDep chunk deps =
  case chunk of
    K.CanopyVar home name -> Set.insert (Global home name) deps
    K.JsVar shortName _ -> Set.insert (toKernelGlobal shortName) deps
    _ -> addKernelDepSimple chunk deps

-- | Handle simple kernel dependency chunks.
--
-- Processes simple kernel chunks that don't create dependencies
-- and returns the dependency set unchanged.
--
-- @since 0.19.1
addKernelDepSimple :: K.Chunk -> Set Global -> Set Global
addKernelDepSimple chunk deps =
  case chunk of
    K.JS _ -> deps
    K.CanopyField _ -> deps
    K.JsField _ -> deps
    K.JsEnum _ -> deps
    K.Debug -> deps
    K.Prod -> deps
    _ -> deps  -- Handle any remaining cases

-- | Convert kernel name to global reference.
--
-- Creates a global reference for a kernel function with the proper
-- kernel package module name and standard kernel naming convention.
-- Kernel modules belong to elm/core package.
--
-- @since 0.19.1
toKernelGlobal :: Name.Name -> Global
toKernelGlobal shortName =
  Global (ModuleName.Canonical Pkg.kernel shortName) Name.dollar

-- INSTANCES

instance Eq Global where
  (==) (Global home1 name1) (Global home2 name2) =
    name1 == name2 && home1 == home2  -- Note: Global is a constructor, not a record

instance Ord Global where
  compare (Global home1 name1) (Global home2 name2) =
    case compare name1 name2 of
      LT -> LT
      EQ -> compare home1 home2
      GT -> GT  -- Note: Global is a constructor, not a record

-- BINARY

instance Binary.Binary Global where
  get = Monad.liftM2 Global Binary.get Binary.get
  put (Global a b) = Binary.put a >> Binary.put b  -- Note: Global is a constructor, not a record

instance Binary.Binary Expr where
  put = putExpr
  get = getExpr

-- | Serialize an expression to binary format.
--
-- Efficiently serializes optimized expressions to binary representation
-- for compilation caching and inter-module communication.
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
-- Handles serialization of more complex expression types like floats
-- and variable references.
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
-- Handles serialization of different variable reference types including
-- boxed, cycle, debug, and kernel variables.
--
-- @since 0.19.1
putExprVar :: Expr -> Binary.Put
putExprVar expr = case expr of
  VarBox a -> Binary.putWord8 8 >> Binary.put a
  VarCycle a b -> Binary.putWord8 9 >> Binary.put a >> Binary.put b
  VarDebug a b c d -> Binary.putWord8 10 >> Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d
  VarKernel a b -> Binary.putWord8 11 >> Binary.put a >> Binary.put b
  _ -> putExprControl expr

-- | Serialize control flow expressions to binary format.
--
-- Handles serialization of control flow constructs like function calls,
-- tail calls, and list expressions.
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
-- Handles serialization of data manipulation expressions like conditionals,
-- let bindings, destructuring, and case expressions.
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
-- Handles serialization of record operations, tuple construction,
-- and shader expressions.
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
  _ -> InternalError.report
    "AST.Optimized.putExprRecord"
    "unexpected expression in putExprRecord"
    "putExprRecord only handles optimized expression types up to Shader (tag 26). Encountering an unknown expression here indicates a new expression constructor was added without updating the Binary serialization."

-- | Deserialize an expression from binary format.
--
-- Efficiently deserializes optimized expressions from binary representation
-- with proper error handling for corrupted data.
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
    _ -> fail "problem getting Opt.Expr binary"

-- | Deserialize simple expressions (Bool, Chr, Str, Int, Float).
--
-- Handles deserialization of basic literal expressions with
-- efficient tag-based dispatch.
--
-- @since 0.19.1
getExprSimple :: Word8 -> Binary.Get Expr
getExprSimple word = case word of
  0 -> fmap Bool Binary.get
  1 -> fmap Chr Binary.get
  2 -> fmap Str Binary.get
  3 -> fmap Int Binary.get
  4 -> fmap Float Binary.get
  _ -> fail "getExprSimple: unexpected word"

-- | Deserialize variable expressions.
--
-- Handles deserialization of different variable reference types
-- with proper reconstruction of metadata.
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
  11 -> Monad.liftM2 VarKernel Binary.get Binary.get
  _ -> fail "getExprVar: unexpected word"

-- | Deserialize control flow expressions.
--
-- Handles deserialization of control flow constructs with
-- proper reconstruction of nested structures.
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
  _ -> fail "getExprControl: unexpected word"

-- | Deserialize data structure expressions.
--
-- Handles deserialization of data manipulation expressions with
-- proper reconstruction of complex nested data.
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
  _ -> fail "getExprData: unexpected word"

instance Binary.Binary Def where
  put def =
    case def of
      Def a b -> Binary.putWord8 0 >> Binary.put a >> Binary.put b
      TailDef a b c -> Binary.putWord8 1 >> Binary.put a >> Binary.put b >> Binary.put c

  get =
    do
      word <- Binary.getWord8
      case word of
        0 -> Monad.liftM2 Def Binary.get Binary.get
        1 -> Monad.liftM3 TailDef Binary.get Binary.get Binary.get
        _ -> fail "problem getting Opt.Def binary"

instance Binary.Binary Destructor where
  get = Monad.liftM2 Destructor Binary.get Binary.get
  put (Destructor a b) = Binary.put a >> Binary.put b  -- Note: Destructor is a constructor, not a record

instance Binary.Binary Path where
  put destructor =
    case destructor of
      Index a b -> Binary.putWord8 0 >> Binary.put a >> Binary.put b
      Field a b -> Binary.putWord8 1 >> Binary.put a >> Binary.put b
      Unbox a -> Binary.putWord8 2 >> Binary.put a
      Root a -> Binary.putWord8 3 >> Binary.put a

  get =
    do
      word <- Binary.getWord8
      case word of
        0 -> Monad.liftM2 Index Binary.get Binary.get
        1 -> Monad.liftM2 Field Binary.get Binary.get
        2 -> fmap Unbox Binary.get
        3 -> fmap Root Binary.get
        _ -> fail "problem getting Opt.Path binary"

instance (Binary.Binary a) => Binary.Binary (Decider a) where
  put decider =
    case decider of
      Leaf a -> Binary.putWord8 0 >> Binary.put a
      Chain a b c -> Binary.putWord8 1 >> Binary.put a >> Binary.put b >> Binary.put c
      FanOut a b c -> Binary.putWord8 2 >> Binary.put a >> Binary.put b >> Binary.put c

  get =
    do
      word <- Binary.getWord8
      case word of
        0 -> fmap Leaf Binary.get
        1 -> Monad.liftM3 Chain Binary.get Binary.get Binary.get
        2 -> Monad.liftM3 FanOut Binary.get Binary.get Binary.get
        _ -> fail "problem getting Opt.Decider binary"

instance Binary.Binary Choice where
  put choice =
    case choice of
      Inline expr -> Binary.putWord8 0 >> Binary.put expr
      Jump index -> Binary.putWord8 1 >> Binary.put index

  get =
    do
      word <- Binary.getWord8
      case word of
        0 -> fmap Inline Binary.get
        1 -> fmap Jump Binary.get
        _ -> fail "problem getting Opt.Choice binary"

instance Binary.Binary GlobalGraph where
  -- Backwards compatible get: old format has 2 fields, new has 3
  -- The sourceLocations field was added for source map support
  get = do
    nodes <- Binary.get
    fields <- Binary.get
    locs <- Binary.get <|> pure Map.empty
    pure (GlobalGraph nodes fields locs)
  put (GlobalGraph a b c) = Binary.put a >> Binary.put b >> Binary.put c

instance Binary.Binary LocalGraph where
  get = Monad.liftM4 LocalGraph Binary.get Binary.get Binary.get Binary.get
  put (LocalGraph a b c d) = Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d

instance Binary.Binary Main where
  put main =
    case main of
      Static -> Binary.putWord8 0
      Dynamic a b -> Binary.putWord8 1 >> Binary.put a >> Binary.put b
      TestMain -> Binary.putWord8 2

  get =
    do
      word <- Binary.getWord8
      case word of
        0 -> return Static
        1 -> Monad.liftM2 Dynamic Binary.get Binary.get
        2 -> return TestMain
        _ -> fail "problem getting Opt.Main binary"

instance Binary.Binary Node where
  put = putNode
  get = getNode

-- | Serialize a node to binary format.
--
-- Efficiently serializes dependency graph nodes to binary representation
-- for module caching and incremental compilation.
--
-- @since 0.19.1
putNode :: Node -> Binary.Put
putNode node = case node of
  Define a b -> Binary.putWord8 0 >> Binary.put a >> Binary.put b
  DefineTailFunc a b c -> Binary.putWord8 1 >> Binary.put a >> Binary.put b >> Binary.put c
  Ctor a b -> Binary.putWord8 2 >> Binary.put a >> Binary.put b
  Enum a -> Binary.putWord8 3 >> Binary.put a
  _ -> putNodeComplex node

-- | Serialize complex nodes to binary format.
--
-- Handles serialization of more complex node types like cycles,
-- managers, and special effect-related nodes.
--
-- @since 0.19.1
putNodeComplex :: Node -> Binary.Put
putNodeComplex node = case node of
  Box -> Binary.putWord8 4
  Link a -> Binary.putWord8 5 >> Binary.put a
  Cycle a b c d -> Binary.putWord8 6 >> Binary.put a >> Binary.put b >> Binary.put c >> Binary.put d
  Manager a -> Binary.putWord8 7 >> Binary.put a
  _ -> putNodeSpecial node

-- | Serialize special nodes to binary format.
--
-- Handles serialization of special node types like kernel functions
-- and port definitions.
--
-- @since 0.19.1
putNodeSpecial :: Node -> Binary.Put
putNodeSpecial node = case node of
  Kernel a b -> Binary.putWord8 8 >> Binary.put a >> Binary.put b
  PortIncoming a b -> Binary.putWord8 9 >> Binary.put a >> Binary.put b
  PortOutgoing a b -> Binary.putWord8 10 >> Binary.put a >> Binary.put b
  _ -> InternalError.report
    "AST.Optimized.putNodeSpecial"
    "unexpected node in putNodeSpecial"
    "putNodeSpecial only handles Kernel, PortIncoming, and PortOutgoing nodes. Other node types must be serialized by the main putNode function."

-- | Deserialize a node from binary format.
--
-- Efficiently deserializes dependency graph nodes from binary
-- representation with proper error handling.
--
-- @since 0.19.1
getNode :: Binary.Get Node
getNode = do
  word <- Binary.getWord8
  case word of
    n | n <= 4 -> getNodeSimple n
    n | n <= 10 -> getNodeComplex n
    _ -> fail "problem getting Opt.Node binary"

-- | Deserialize simple nodes.
--
-- Handles deserialization of basic node types like definitions
-- and constructors.
--
-- @since 0.19.1
getNodeSimple :: Word8 -> Binary.Get Node
getNodeSimple word = case word of
  0 -> Monad.liftM2 Define Binary.get Binary.get
  1 -> Monad.liftM3 DefineTailFunc Binary.get Binary.get Binary.get
  2 -> Monad.liftM2 Ctor Binary.get Binary.get
  3 -> fmap Enum Binary.get
  4 -> return Box
  _ -> fail "getNodeSimple: unexpected word"

-- | Deserialize complex nodes.
--
-- Handles deserialization of complex node types with proper
-- reconstruction of dependency information.
--
-- @since 0.19.1
getNodeComplex :: Word8 -> Binary.Get Node
getNodeComplex word = case word of
  5 -> fmap Link Binary.get
  6 -> Monad.liftM4 Cycle Binary.get Binary.get Binary.get Binary.get
  7 -> fmap Manager Binary.get
  8 -> Monad.liftM2 Kernel Binary.get Binary.get
  9 -> Monad.liftM2 PortIncoming Binary.get Binary.get
  10 -> Monad.liftM2 PortOutgoing Binary.get Binary.get
  _ -> fail "getNodeComplex: unexpected word"

instance Binary.Binary EffectsType where
  put effectsType =
    case effectsType of
      Cmd -> Binary.putWord8 0
      Sub -> Binary.putWord8 1
      Fx -> Binary.putWord8 2

  get =
    do
      word <- Binary.getWord8
      case word of
        0 -> return Cmd
        1 -> return Sub
        2 -> return Fx
        _ -> fail "problem getting Opt.EffectsType binary"

