-- | Graph types and operations for the Optimized AST.
--
-- This module defines the dependency graph types used in the Canopy compiler
-- for link-time optimization, dead code elimination, and code generation
-- ordering. It also provides the graph operations used to build and combine
-- these dependency graphs.
--
-- These types are separated from "AST.Optimized" to keep each module under
-- the 800-line limit while avoiding circular imports.
--
-- @since 0.19.1
module AST.Optimized.Graph
  ( GlobalGraph (..),
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
import AST.Optimized.Expr (Def, Expr, Global (..))
import qualified Canopy.Data.Index as Index
import Canopy.Data.Name (Name)
import qualified Canopy.Data.Name as Name
import qualified Canopy.Kernel as Kernel
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Applicative ((<|>))
import qualified Control.Monad as Monad
import qualified Data.Binary as Binary
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Word (Word8)
import qualified Reporting.Annotation as Ann
import qualified Reporting.InternalError as InternalError

-- TYPES

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
    _g_sourceLocations :: Map Global Ann.Region
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
    _l_nodes :: Map Global Node,
    -- | Field usage counts for optimization
    _l_fields :: Map Name Int,
    -- | Source locations for each global, used for source map generation
    _l_sourceLocations :: Map Global Ann.Region
  }
  deriving (Show)

-- | Main function specification for applications.
--
-- @since 0.19.1
data Main
  = -- | Static application without runtime messages.
    Static
  | -- | Dynamic application with message handling.
    Dynamic
      { _message :: Can.Type,
        _decoder :: Expr
      }
  | -- | Test or non-visual main that should be exported as a raw value.
    TestMain
  | -- | Browser test main that runs in a real browser via Playwright.
    BrowserTestMain
  deriving (Show)

-- | Dependency graph node representing definitions.
--
-- @since 0.19.1
data Node
  = -- | Simple definition with dependencies.
    Define Expr (Set Global)
  | -- | Tail-optimized function definition.
    DefineTailFunc [Name] Expr (Set Global)
  | -- | Constructor definition.
    Ctor Index.ZeroBased Int
  | -- | Enumeration constructor.
    Enum Index.ZeroBased
  | -- | Boxed constructor.
    Box
  | -- | Link to another global definition.
    Link Global
  | -- | Recursive definition cycle.
    Cycle [Name] [(Name, Expr)] [Def] (Set Global)
  | -- | Effect manager definition.
    Manager EffectsType
  | -- | Kernel function definition.
    Kernel [Kernel.Chunk] (Set Global)
  | -- | Incoming port definition.
    PortIncoming Expr (Set Global)
  | -- | Outgoing port definition.
    PortOutgoing Expr (Set Global)
  deriving (Show)

-- | Effect type classification for effect managers.
--
-- @since 0.19.1
data EffectsType
  = -- | Command effects.
    Cmd
  | -- | Subscription effects.
    Sub
  | -- | Combined command and subscription effects.
    Fx
  deriving (Show)

-- GRAPH OPERATIONS

-- | Create an empty global dependency graph.
--
-- @since 0.19.1
{-# NOINLINE empty #-}
empty :: GlobalGraph
empty =
  GlobalGraph Map.empty Map.empty Map.empty

-- | Combine two global dependency graphs.
--
-- Merges two global graphs by taking the union of their nodes and fields.
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
-- by merging nodes and field information. Main function info is discarded.
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
-- chunks and computed dependencies.
--
-- @since 0.19.1
addKernel :: Name.Name -> [Kernel.Chunk] -> GlobalGraph -> GlobalGraph
addKernel shortName chunks (GlobalGraph nodes fields locs) =
  let global = toKernelGlobal shortName
      node = Kernel chunks (foldr addKernelDep Set.empty chunks)
   in GlobalGraph
        { _g_nodes = Map.insert global node nodes,
          _g_fields = Map.union (Kernel.countFields chunks) fields,
          _g_sourceLocations = locs
        }

-- | Convert kernel name to global reference.
--
-- Creates a global reference for a kernel function with the proper
-- kernel package module name.
--
-- @since 0.19.1
toKernelGlobal :: Name.Name -> Global
toKernelGlobal shortName =
  Global (ModuleName.Canonical Pkg.kernel shortName) Name.dollar

-- LOCAL HELPERS

addKernelDep :: Kernel.Chunk -> Set Global -> Set Global
addKernelDep chunk deps =
  case chunk of
    Kernel.CanopyVar home name -> Set.insert (Global home name) deps
    Kernel.JsVar shortName _ -> Set.insert (toKernelGlobal shortName) deps
    _ -> addKernelDepSimple chunk deps

addKernelDepSimple :: Kernel.Chunk -> Set Global -> Set Global
addKernelDepSimple chunk deps =
  case chunk of
    Kernel.JS _ -> deps
    Kernel.CanopyField _ -> deps
    Kernel.JsField _ -> deps
    Kernel.JsEnum _ -> deps
    Kernel.Debug -> deps
    Kernel.Prod -> deps
    _ -> deps

-- BINARY INSTANCES

instance Binary.Binary GlobalGraph where
  -- Backwards compatible get: old format has 2 fields, new has 3.
  -- The sourceLocations field was added for source map support.
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
      BrowserTestMain -> Binary.putWord8 3
  get = do
    word <- Binary.getWord8
    case word of
      0 -> return Static
      1 -> Monad.liftM2 Dynamic Binary.get Binary.get
      2 -> return TestMain
      3 -> return BrowserTestMain
      _ -> fail "problem getting Opt.Main binary"

instance Binary.Binary Node where
  put = putNode
  get = getNode

-- | Serialize a node to binary format.
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
-- @since 0.19.1
putNodeSpecial :: Node -> Binary.Put
putNodeSpecial node = case node of
  Kernel a b -> Binary.putWord8 8 >> Binary.put a >> Binary.put b
  PortIncoming a b -> Binary.putWord8 9 >> Binary.put a >> Binary.put b
  PortOutgoing a b -> Binary.putWord8 10 >> Binary.put a >> Binary.put b
  _ ->
    InternalError.report
      "AST.Optimized.Graph.putNodeSpecial"
      "unexpected node in putNodeSpecial"
      "putNodeSpecial only handles Kernel, PortIncoming, and PortOutgoing nodes."

-- | Deserialize a node from binary format.
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
  get = do
    word <- Binary.getWord8
    case word of
      0 -> return Cmd
      1 -> return Sub
      2 -> return Fx
      _ -> fail "problem getting Opt.EffectsType binary"
