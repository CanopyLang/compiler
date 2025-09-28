{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Core type definitions for the Generate subsystem.
--
-- This module provides the fundamental data types used throughout the
-- code generation pipeline, including loading states and object containers.
--
-- The type system follows a phased approach:
--
-- @
-- LoadingObjects -> Objects -> Generated Code
-- @
--
-- === Usage Examples
--
-- @
-- -- Create loading objects container
-- loading <- createLoadingObjects foreignTVar localMVars
-- 
-- -- Convert to finalized objects
-- objects <- finalizeToObjects loading
-- @
--
-- === Thread Safety
--
-- All types in this module are designed for concurrent access through
-- MVar-based synchronization. Loading operations can be performed in
-- parallel while maintaining consistency.
--
-- @since 0.19.1
module Generate.Types
  ( -- * Loading Types
    LoadingObjects(..)
  , Objects(..)
    -- * Type Aliases
  , Task
    -- * Constructors
  , createLoadingObjects
  , createObjects
    -- * Lenses
  , foreign_tvarL
  , local_tvarsL
  , foreignGraph
  , localGraphs
  ) where

import qualified AST.Optimized as Opt
import Control.Concurrent.STM (TVar)
import Control.Lens (Lens', lens)
import Data.Map (Map)
import qualified Canopy.ModuleName as ModuleName
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task

-- | Type alias for generation tasks that can fail with generation errors.
type Task a = Task.Task Exit.Generate a

-- | Container for objects being loaded concurrently.
--
-- This type represents the intermediate state where object loading
-- is in progress. Foreign objects and local modules are loaded
-- using MVars to enable parallel loading operations.
--
-- === Fields
--
-- * '_foreign_tvar': TVar containing the global foreign object graph
-- * '_local_tvars': Map of module names to TVars containing local graphs
--
-- === Usage
--
-- @
-- loading <- createLoadingObjects foreignTVar localTVars
-- objects <- finalizeToObjects loading
-- @
data LoadingObjects = LoadingObjects
  { _foreign_tvar :: !(TVar (Maybe Opt.GlobalGraph))
    -- ^ TVar containing the global foreign object graph
  , _local_tvars :: !(Map ModuleName.Raw (TVar (Maybe Opt.LocalGraph)))
    -- ^ Map of module names to TVars containing local graphs
  }

-- | Container for finalized objects ready for code generation.
--
-- This type represents the final state where all loading is complete
-- and objects are ready for the code generation phase.
--
-- === Fields
--
-- * '_foreign': The global foreign object graph
-- * '_locals': Map of module names to local graphs
--
-- === Usage
--
-- @
-- let graph = objectsToGlobalGraph objects
-- let mains = gatherMains pkg objects roots
-- JS.generate mode graph mains
-- @
data Objects = Objects
  { _foreign :: !Opt.GlobalGraph
    -- ^ The global foreign object graph
  , _locals :: !(Map ModuleName.Raw Opt.LocalGraph)
    -- ^ Map of module names to local graphs
  } deriving (Show)

-- Manual lenses for LoadingObjects
foreign_tvarL :: Lens' LoadingObjects (TVar (Maybe Opt.GlobalGraph))
foreign_tvarL = lens _foreign_tvar (\s x -> s { _foreign_tvar = x })

local_tvarsL :: Lens' LoadingObjects (Map ModuleName.Raw (TVar (Maybe Opt.LocalGraph)))
local_tvarsL = lens _local_tvars (\s x -> s { _local_tvars = x })

-- Manual lenses for Objects with safe names  
foreignGraph :: Lens' Objects Opt.GlobalGraph
foreignGraph = lens _foreign (\s x -> s { _foreign = x })

localGraphs :: Lens' Objects (Map ModuleName.Raw Opt.LocalGraph) 
localGraphs = lens _locals (\s x -> s { _locals = x })

-- | Create a LoadingObjects container.
--
-- This function constructs a LoadingObjects container from the provided
-- TVars for foreign and local object graphs.
--
-- === Parameters
--
-- * 'foreignTVar': TVar containing the global foreign object graph
-- * 'localTVars': Map of module names to TVars containing local graphs
--
-- === Returns
--
-- A LoadingObjects container ready for finalization.
--
-- === Examples
--
-- @
-- loading <- createLoadingObjects foreignTVar localTVars
-- @
--
-- @since 0.19.1
createLoadingObjects
  :: TVar (Maybe Opt.GlobalGraph)
  -- ^ TVar containing the global foreign object graph
  -> Map ModuleName.Raw (TVar (Maybe Opt.LocalGraph))
  -- ^ Map of module names to TVars containing local graphs
  -> LoadingObjects
  -- ^ LoadingObjects container
createLoadingObjects foreignTVar localTVars =
  LoadingObjects foreignTVar localTVars

-- | Create an Objects container.
--
-- This function constructs an Objects container from finalized
-- foreign and local object graphs.
--
-- === Parameters
--
-- * 'foreignGraph': The global foreign object graph
-- * 'locals': Map of module names to local graphs
--
-- === Returns
--
-- An Objects container ready for code generation.
--
-- === Examples
--
-- @
-- objects <- createObjects foreignGraph localGraphs
-- @
--
-- @since 0.19.1
createObjects 
  :: Opt.GlobalGraph
  -- ^ The global foreign object graph
  -> Map ModuleName.Raw Opt.LocalGraph
  -- ^ Map of module names to local graphs
  -> Objects
  -- ^ Objects container
createObjects foreignGraph' locals' = 
  Objects foreignGraph' locals'