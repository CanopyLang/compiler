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
-- loading <- createLoadingObjects foreignMVar localMVars
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
  , foreign_mvarL
  , local_mvarsL
  , foreignGraph
  , localGraphs
  ) where

import qualified AST.Optimized as Opt
import Control.Concurrent (MVar)
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
-- * '_foreign_mvar': MVar containing the global foreign object graph
-- * '_local_mvars': Map of module names to MVars containing local graphs
--
-- === Usage
--
-- @
-- loading <- createLoadingObjects foreignMVar localMVars
-- objects <- finalizeToObjects loading
-- @
data LoadingObjects = LoadingObjects
  { _foreign_mvar :: !(MVar (Maybe Opt.GlobalGraph))
    -- ^ MVar containing the global foreign object graph
  , _local_mvars :: !(Map ModuleName.Raw (MVar (Maybe Opt.LocalGraph)))
    -- ^ Map of module names to MVars containing local graphs
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
foreign_mvarL :: Lens' LoadingObjects (MVar (Maybe Opt.GlobalGraph))
foreign_mvarL = lens _foreign_mvar (\s x -> s { _foreign_mvar = x })

local_mvarsL :: Lens' LoadingObjects (Map ModuleName.Raw (MVar (Maybe Opt.LocalGraph)))
local_mvarsL = lens _local_mvars (\s x -> s { _local_mvars = x })

-- Manual lenses for Objects with safe names  
foreignGraph :: Lens' Objects Opt.GlobalGraph
foreignGraph = lens _foreign (\s x -> s { _foreign = x })

localGraphs :: Lens' Objects (Map ModuleName.Raw Opt.LocalGraph) 
localGraphs = lens _locals (\s x -> s { _locals = x })

-- | Create a LoadingObjects container.
--
-- This function constructs a LoadingObjects container from the provided
-- MVars for foreign and local object graphs.
--
-- === Parameters
--
-- * 'foreignMVar': MVar containing the global foreign object graph
-- * 'localMVars': Map of module names to MVars containing local graphs
--
-- === Returns
--
-- A LoadingObjects container ready for finalization.
--
-- === Examples
--
-- @
-- loading <- createLoadingObjects foreignMVar localMVars
-- @
--
-- @since 0.19.1
createLoadingObjects 
  :: MVar (Maybe Opt.GlobalGraph)
  -- ^ MVar containing the global foreign object graph
  -> Map ModuleName.Raw (MVar (Maybe Opt.LocalGraph))
  -- ^ Map of module names to MVars containing local graphs
  -> LoadingObjects
  -- ^ LoadingObjects container
createLoadingObjects foreignMVar localMVars = 
  LoadingObjects foreignMVar localMVars

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